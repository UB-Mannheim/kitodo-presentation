<?php
// Minimal Apache Solr HTTP emulation for the Kitodo.Presentation demo.
//
// The dlf extension talks to Solr through Solarium over plain HTTP. This module
// implements just enough of the Solr JSON API for the read-only demo plugins
// (dlf_search, dlf_listview, dlf_collection, dlf_statistics) to work without a
// real Solr server:
//
//   * GET  /admin/cores?core=<core>&action=STATUS
//         -> the Solr instance's constructor probes this and only marks itself
//            "ready" when status.<core>.uptime > 0 (see Classes/Common/Solr/
//            Solr.php::__construct). Must therefore report a positive uptime.
//   * GET/POST /<core>/select
//         -> the search / list view / collection "show" results. The code always
//            adds result grouping by "uid" (SolrSearch::searchSolr) and reads
//            response.grouped.uid.{matches,ngroups,groups[].doclist.docs}.
//            Facet sub-requests read response.facet_counts.facet_fields.<field>.
//            Collection "list" uses flat response.docs (Solr::searchRaw).
//   * POST /<core>/update
//         -> the real indexer (IndexCommand / Indexer::add) pushes documents here
//            as JSON add + delete + commit operations.
//
// The module is written to be included from the demo's static data router
// (data-router.php): it inspects the current request, and if the path is under
// the Solr prefix it emits the JSON response and returns true (claiming the
// request). Otherwise it returns false so the router falls through to static
// file serving. Nothing here depends on TYPO3 or Solarium.

/**
 * The URL prefix the extension's Solr client is pointed at (see solr.path in the
 * ext config, e.g. "solr" -> the client requests /solr/<core>/select).
 */
define('DLF_SOLR_PREFIX', 'solr');

/**
 * Default file the emulator reads/writes its document catalog from. Located
 * inside the data server's document root so it is writable by the same
 * php -S process. Override with the DLF_SOLR_DATA environment variable.
 */
function dlf_solr_data_file(): string
{
    $base = getenv('DLF_SOLR_DATA') !== false
        ? (string) getenv('DLF_SOLR_DATA')
        : (string) ($_SERVER['DOCUMENT_ROOT'] ?? __DIR__);
    return $base . '/.solr-catalog.json';
}

/**
 * Entry point. Returns true when this request was a Solr request and has been
 * fully handled (response already sent), false otherwise.
 *
 * @param array|null $server Overridable superglobal for testing (defaults to $_SERVER).
 */
function dlf_solr_handle_request(?array $server = null): bool
{
    $server = $server ?? $_SERVER;
    $path = (string) (parse_url($server['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?? '/');
    $prefix = '/' . DLF_SOLR_PREFIX . '/';
    if (!str_starts_with($path, $prefix)) {
        return false;
    }

    $segments = array_values(array_filter(explode('/', substr($path, strlen($prefix))), 'strlen'));
    // Segments after the prefix: [<core>, <handler>] (admin cores use "admin/cores").
    $core = $segments[0] ?? null;
    $handler = $segments[1] ?? null;

    $docs = dlf_solr_load_catalog();
    $isPost = ($server['REQUEST_METHOD'] ?? 'GET') === 'POST';

    try {
        if ($core === 'admin' && $handler === 'cores') {
            dlf_solr_send(dlf_solr_core_status($docs, $server));
        } elseif ($handler === 'select') {
            $params = dlf_solr_request_params($server, $isPost);
            dlf_solr_send(dlf_solr_select($params, $docs));
        } elseif ($handler === 'update') {
            $body = (string) ($server['REQUEST_BODY'] ?? file_get_contents('php://input'));
            $data = json_decode($body ?: '{}', true) ?: [];
            $deleted = dlf_solr_update($data, $docs);
            dlf_solr_save_catalog($docs);
            dlf_solr_send(['responseHeader' => dlf_solr_header(), 'add' => [], 'deleted' => $deleted, 'status' => 0]);
        } else {
            dlf_solr_send(['responseHeader' => dlf_solr_header(), 'error' => ['msg' => 'unsupported handler', 'code' => 400]], 400);
        }
    } catch (\Throwable $e) {
        dlf_solr_send(['responseHeader' => dlf_solr_header(), 'error' => ['msg' => $e->getMessage(), 'code' => 500]], 500);
    }
    return true;
}

// ---------------------------------------------------------------------------
// Catalog (in-memory document store, persisted to a JSON file)
// ---------------------------------------------------------------------------

function dlf_solr_load_catalog(): array
{
    $file = dlf_solr_data_file();
    if (is_file($file)) {
        $decoded = json_decode((string) file_get_contents($file), true);
        if (is_array($decoded) && isset($decoded['docs']) && is_array($decoded['docs'])) {
            return $decoded['docs'];
        }
    }
    return [];
}

function dlf_solr_save_catalog(array $docs): void
{
    $file = dlf_solr_data_file();
    $dir = dirname($file);
    if (!is_dir($dir)) {
        @mkdir($dir, 0777, true);
    }
    file_put_contents($file, json_encode(['docs' => $docs], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE));
}

/**
 * The unique document id in the catalog. The dlf indexer uses
 * "<uid><xmlId>" (e.g. "1001LOG_0000") for the Solr "id" field.
 *
 * @return string
 */
function dlf_solr_doc_id(array $doc): string
{
    if (isset($doc['id']) && $doc['id'] !== '') {
        return (string) $doc['id'];
    }
    return (string) (($doc['uid'] ?? 'doc') . '::__' . spl_object_id($doc));
}

// ---------------------------------------------------------------------------
// HTTP helpers
// ---------------------------------------------------------------------------

function dlf_solr_header(): array
{
    static $start = null;
    $start ??= microtime(true);
    return [
        'status' => 0,
        'QTime' => max(1, (int) round((microtime(true) - $start) * 1000)),
        'params' => [],
    ];
}

function dlf_solr_send(array $payload, int $status = 200): void
{
    http_response_code($status);
    header('Content-Type: application/json; charset=UTF-8');
    echo json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE);
}

/**
 * Merge the query string, POST form fields and (for POST) JSON body into a
 * flat parameter list. Arrays (e.g. filterquery, facet.field) are collapsed to
 * repeated scalar keys, matching how Solarium serializes them. The raw query
 * string / form body is parsed with a dot-preserving parser (PHP's parse_str
 * rewrites "." to "_", which would corrupt names like "group.field" and
 * "f.<field>.facet.*").
 *
 * @return array<string, list<string>>
 */
function dlf_solr_request_params(array $server, bool $isPost): array
{
    $params = [];
    dlf_solr_flatten(dlf_solr_parse_qs((string) ($server['QUERY_STRING'] ?? '')), $params);

    if ($isPost) {
        $contentType = (string) ($server['CONTENT_TYPE'] ?? '');
        $body = (string) ($server['REQUEST_BODY'] ?? file_get_contents('php://input'));
        if (stripos($contentType, 'application/json') !== false) {
            $json = json_decode($body, true);
            if (is_array($json)) {
                dlf_solr_flatten($json, $params);
            }
        } elseif ($body !== '') {
            dlf_solr_flatten(dlf_solr_parse_qs($body), $params);
        }
    }
    return $params;
}

/**
 * Parse a URL-encoded query string / form body into a list-keyed array,
 * preserving exact key names (including "."). Unlike parse_str it does not
 * rewrite dots to underscores, so Solr's dotted parameter names survive.
 *
 * @return array<string, list<string>>
 */
function dlf_solr_parse_qs(string $qs): array
{
    $out = [];
    if ($qs === '') {
        return $out;
    }
    foreach (explode('&', $qs) as $pair) {
        if ($pair === '') {
            continue;
        }
        $eq = strpos($pair, '=');
        $key = $eq === false ? $pair : substr($pair, 0, $eq);
        $value = $eq === false ? '' : substr($pair, $eq + 1);
        $key = dlf_solr_urldecode($key);
        if ($key === '') {
            continue;
        }
        $out[$key][] = dlf_solr_urldecode($value);
    }
    return $out;
}

/**
 * URL-decode a single value, restoring "+" as space and %XX sequences.
 */
function dlf_solr_urldecode(string $value): string
{
    $decoded = urldecode(str_replace('+', ' ', $value));
    return $decoded === false ? $value : $decoded;
}

/**
 * Recursively flatten a nested parameter array into scalar keys with list
 * values, dropping array sub-structures that carry only non-scalar children.
 */
function dlf_solr_flatten(array $input, array &$out): void
{
    foreach ($input as $key => $value) {
        if (is_array($value)) {
            if (array_is_list($value)) {
                foreach ($value as $item) {
                    if (is_array($item)) {
                        // e.g. filterquery[] = { query: "..." } -> take the query value.
                        if (isset($item['query']) && is_scalar($item['query'])) {
                            $out[(string) $key][] = (string) $item['query'];
                        }
                    } else {
                        $out[(string) $key][] = (string) $item;
                    }
                }
            } else {
                dlf_solr_flatten($value, $out);
            }
        } elseif (is_bool($value)) {
            $out[(string) $key][] = $value ? 'true' : 'false';
        } else {
            $out[(string) $key][] = (string) $value;
        }
    }
}

function dlf_solr_get(array $params, string $key, ?string $default = null): ?string
{
    return isset($params[$key][0]) ? $params[$key][0] : $default;
}

function dlf_solr_all(array $params, string $key): array
{
    return isset($params[$key]) ? $params[$key] : [];
}

// ---------------------------------------------------------------------------
// Core admin
// ---------------------------------------------------------------------------

/**
 * Build the core STATUS response. uptime must be > 0 for the client to consider
 * the core available (Solr.php checks getUptime() > 0).
 */
function dlf_solr_core_status(array $docs, array $server): array
{
    $qs = dlf_solr_parse_qs((string) ($server['QUERY_STRING'] ?? ''));
    $core = (string) (($qs['core'][0] ?? ''));
    $numDocs = count($docs);
    $now = time();
    $status = [
        'index' => [
            'numDocs' => $numDocs,
            'maxDoc' => $numDocs,
            'delCount' => 0,
            'version' => 1,
            'lastModified' => gmdate('Y-m-d\TH:i:s.u\Z'),
        ],
        'uptime' => 3600000,
        'startTime' => gmdate('Y-m-d\TH:i:s\Z', $now - 3600),
    ];
    return [
        'responseHeader' => dlf_solr_header(),
        // When no specific core is requested the client only needs the action to
        // succeed; when a core is requested it is keyed by that name.
        'status' => $core !== '' ? [$core => $status] : [],
        'initFailures' => [],
    ];
}

// ---------------------------------------------------------------------------
// Update (indexing)
// ---------------------------------------------------------------------------

/**
 * Apply a JSON update payload (add / delete / commit) to the catalog.
 * Returns the number of docs deleted (for the response).
 *
 * @param array $data Decoded JSON body.
 */
function dlf_solr_update(array $data, array &$docs): int
{
    $deleted = 0;

    if (isset($data['add']) && is_array($data['add'])) {
        foreach ($data['add'] as $doc) {
            if (!is_array($doc)) {
                continue;
            }
            $id = dlf_solr_doc_id($doc);
            // Replace any existing doc with the same id (Solr upserts by unique key).
            $docs = array_filter($docs, fn (array $d) => dlf_solr_doc_id($d) !== $id);
            $docs[] = $doc;
        }
        $docs = array_values($docs);
    }

    if (isset($data['delete']) && is_array($data['delete'])) {
        foreach ($data['delete'] as $del) {
            if (is_array($del) && isset($del['id']) && is_array($del['id'])) {
                $ids = array_map('strval', $del['id']);
                foreach ($docs as $i => $doc) {
                    if (in_array(dlf_solr_doc_id($doc), $ids, true)) {
                        unset($docs[$i]);
                        $deleted++;
                    }
                }
            } elseif (is_array($del) && isset($del['query'])) {
                // e.g. "uid:1001" or "location:..."
                $fieldValue = explode(':', (string) $del['query'], 2);
                if (count($fieldValue) === 2) {
                    [$field, $value] = $fieldValue;
                    $value = trim($value, '"');
                    foreach ($docs as $i => $doc) {
                        if (dlf_solr_field_matches($doc, $field, $value)) {
                            unset($docs[$i]);
                            $deleted++;
                        }
                    }
                }
            }
        }
        $docs = array_values($docs);
    }
    // commit / optimize are no-ops for an in-memory store.
    return $deleted;
}

/**
 * True when a doc's field equals / contains the given scalar value (used by
 * delete-by-query). Matches both scalar and multi-valued (list) fields.
 */
function dlf_solr_field_matches(array $doc, string $field, string $value): bool
{
    if (!array_key_exists($field, $doc)) {
        return false;
    }
    $actual = $doc[$field];
    if (is_array($actual)) {
        foreach ($actual as $item) {
            if ((string) $item === $value) {
                return true;
            }
        }
        return false;
    }
    return (string) $actual === $value;
}

// ---------------------------------------------------------------------------
// Select
// ---------------------------------------------------------------------------

/**
 * Evaluate a select request against the catalog and build the Solr JSON
 * response (grouped and/or flat, with facets and an always-present empty
 * ocrHighlighting so fulltext searches do not fatal on a missing key).
 */
function dlf_solr_select(array $params, array $docs): array
{
    $query = dlf_solr_get($params, 'q', '*');
    $filterQueries = dlf_solr_all($params, 'fq') + dlf_solr_all($params, 'filterquery');
    $groupingField = dlf_solr_get($params, 'group.field');
    $isGrouped = $groupingField !== null && $groupingField !== '' && dlf_solr_get($params, 'group') === 'true';
    $start = (int) (dlf_solr_get($params, 'start', '0') ?? 0);
    $rows = (int) (dlf_solr_get($params, 'rows', '10') ?? 10);
    $limit = $rows < 0 ? null : $rows; // -1 => all
    $offset = $start < 0 ? 0 : $start;
    $sort = dlf_solr_get($params, 'sort', 'score desc');

    // 1. Match.
    $matchIds = dlf_solr_match($query, $docs);
    $matched = [];
    foreach ($docs as $doc) {
        $id = dlf_solr_doc_id($doc);
        if (!in_array($id, $matchIds, true)) {
            continue;
        }
        if (!dlf_solr_matches_filters($filterQueries, $doc)) {
            continue;
        }
        $matched[] = $doc;
    }

    // 2. Sort.
    dlf_solr_sort($matched, $sort);

    $result = ['responseHeader' => dlf_solr_header()];
    $flatCount = count($matched);

    if ($isGrouped) {
        $groups = dlf_solr_group($matched, (string) $groupingField);
        $totalGroups = count($groups);
        $groupSlice = $limit === null
            ? array_slice($groups, $offset)
            : array_slice($groups, $offset, $limit);

        $groupedValue = [
            'matches' => $flatCount,
            'ngroups' => $totalGroups,
            'groups' => [],
        ];
        foreach ($groupSlice as $group) {
            $groupedValue['groups'][] = [
                'groupValue' => $group['value'],
                'doclist' => [
                    'numFound' => count($group['docs']),
                    'start' => 0,
                    'maxScore' => 1.0,
                    'docs' => array_values($group['docs']),
                ],
            ];
        }

        $result['response'] = [
            'numFound' => $flatCount,
            'start' => 0,
            'maxScore' => 1.0,
            'docs' => [],
        ];
        $result['grouped'] = [(string) $groupingField => $groupedValue];
    } else {
        $docSlice = $limit === null
            ? array_slice($matched, $offset)
            : array_slice($matched, $offset, $limit);
        $result['response'] = [
            'numFound' => $flatCount,
            'start' => $offset,
            'maxScore' => 1.0,
            'docs' => array_values($docSlice),
        ];
    }

    // 3. Facets.
    $facetFields = dlf_solr_facet_fields($params);
    if ($facetFields) {
        $result['facet_counts'] = [
            'facet_queries' => (object) [],
            'facet_fields' => dlf_solr_facet_counts($facetFields, $matched),
            'facet_ranges' => (object) [],
            'facet_intervals' => (object) [],
            'facet_heatmaps' => (object) [],
        ];
    }

    // 4. OCR highlighting: always present (empty) so ResultDocument does not
    //    fatal on a missing key for fulltext queries.
    $result['ocrHighlighting'] = (object) [];

    return $result;
}

/**
 * Group matched docs by a field, preserving document order inside each group.
 * @return array<int, array{value: mixed, docs: array<int, array<string,mixed>}>>
 */
function dlf_solr_group(array $docs, string $field): array
{
    $groups = [];
    foreach ($docs as $doc) {
        $value = $doc[$field] ?? null;
        $key = is_scalar($value) ? (string) $value : (string) spl_object_id($doc);
        if (!isset($groups[$key])) {
            $groups[$key] = ['value' => $value, 'docs' => []];
        }
        $groups[$key]['docs'][] = $doc;
    }
    return array_values($groups);
}

function dlf_solr_sort(array $docs, string $sort): void
{
    // Solarium serializes the sort array to "field dir,field dir,...".
    $sort = trim($sort);
    if ($sort === '') {
        return;
    }
    $specs = [];
    foreach (explode(',', $sort) as $part) {
        $part = trim($part);
        if ($part === '') {
            continue;
        }
        $parts = array_map('trim', explode(' ', $part, 2));
        // Skip score-only specs (constant in the emulator).
        if ($parts[0] === 'score') {
            continue;
        }
        $specs[] = [$parts[0], strtolower($parts[1] ?? 'asc') === 'desc'];
    }
    if (!$specs) {
        return;
    }
    usort($docs, function (array $a, array $b) use ($specs) {
        foreach ($specs as [$field, $desc]) {
            $av = $a[$field] ?? null;
            $bv = $b[$field] ?? null;
            $av = is_array($av) ? reset($av) : $av;
            $bv = is_array($bv) ? reset($bv) : $bv;
            $av = $av === null ? '' : $av;
            $bv = $bv === null ? '' : $bv;
            $cmp = (is_numeric($av) && is_numeric($bv))
                ? ((float) $av <=> (float) $bv)
                : mb_strtolower((string) $av) <=> mb_strtolower((string) $bv);
            if ($cmp !== 0) {
                return $desc ? -$cmp : $cmp;
            }
        }
        return 0;
    });
}

/**
 * Parse the facet field list from the request. Solarium sends each field as a
 * repeated "facet.field" value, possibly with a leading {!key=... } local-
 * params block, and per-field options as "f.<field>.facet.*". We return a map
 * of fieldName => ['limit'=>int,'mincount'=>int].
 *
 * @return array<string, array{limit:int,mincount:int}>
 */
function dlf_solr_facet_fields(array $params): array
{
    $fields = dlf_solr_all($params, 'facet.field');
    if (!$fields) {
        return [];
    }
    $out = [];
    foreach ($fields as $raw) {
        $name = dlf_solr_strip_local_params($raw);
        if ($name === '') {
            continue;
        }
        $limit = (int) (dlf_solr_get($params, 'f.' . $name . '.facet.limit', dlf_solr_get($params, 'facet.limit', '100')) ?? 100);
        $mincount = (int) (dlf_solr_get($params, 'f.' . $name . '.facet.mincount', dlf_solr_get($params, 'facet.mincount', '1')) ?? 1);
        $out[$name] = ['limit' => $limit, 'mincount' => $mincount];
    }
    return $out;
}

function dlf_solr_facet_counts(array $facetFields, array $matched): array
{
    $out = [];
    foreach ($facetFields as $field => $opts) {
        $counts = [];
        foreach ($matched as $doc) {
            if (!array_key_exists($field, $doc)) {
                continue;
            }
            $values = is_array($doc[$field]) ? $doc[$field] : [$doc[$field]];
            foreach ($values as $value) {
                if ($value === null || $value === '') {
                    continue;
                }
                $key = (string) $value;
                $counts[$key] = ($counts[$key] ?? 0) + 1;
            }
        }
        arsort($counts);
        if ($opts['mincount'] > 1) {
            $counts = array_filter($counts, fn ($c) => $c >= $opts['mincount']);
            arsort($counts);
        }
        if ($opts['limit'] >= 0) {
            $counts = array_slice($counts, 0, $opts['limit'], true);
        }
        $out[$field] = empty($counts) ? (object) [] : $counts;
    }
    return $out;
}

/**
 * Strip a leading {!...} local-params block from a query / field expression.
 */
function dlf_solr_strip_local_params(string $expr): string
{
    if (str_starts_with($expr, '{!')) {
        $close = strpos($expr, '}');
        if ($close !== false) {
            return substr($expr, $close + 1);
        }
    }
    return $expr;
}

// ---------------------------------------------------------------------------
// Query matching
// ---------------------------------------------------------------------------

/**
 * Return the ids of all docs matching the main query string.
 */
function dlf_solr_match(string $query, array $docs): array
{
    $tokens = dlf_solr_tokenize($query);
    $pos = 0;
    $node = dlf_solr_parse_expr($tokens, $pos, false);
    $match = [];
    foreach ($docs as $doc) {
        if (dlf_solr_eval($node, $doc)) {
            $match[] = dlf_solr_doc_id($doc);
        }
    }
    return $match;
}

function dlf_solr_matches_filters(array $filterQueries, array $doc): bool
{
    foreach ($filterQueries as $fq) {
        if (trim((string) $fq) === '') {
            continue;
        }
        $tokens = dlf_solr_tokenize((string) $fq);
        $pos = 0;
        $node = dlf_solr_parse_expr($tokens, $pos, false);
        if (!dlf_solr_eval($node, $doc)) {
            return false;
        }
    }
    return true;
}

/**
 * Tokenize a Solr query into a flat token list. Quoted strings (double quotes
 * or the {!...} local-param block) are kept as single tokens; parentheses and
 * range brackets are separate tokens.
 */
function dlf_solr_tokenize(string $input): array
{
    $input = trim($input);
    $tokens = [];
    $len = strlen($input);
    $i = 0;
    while ($i < $len) {
        $c = $input[$i];
        if (ctype_space($c)) {
            $i++;
            continue;
        }
        if ($c === '(' || $c === ')' || $c === '[' || $c === ']') {
            $tokens[] = $c;
            $i++;
            continue;
        }
        if ($c === '"') {
            $end = strpos($input, '"', $i + 1);
            $end = $end === false ? $len - 1 : $end;
            $tokens[] = substr($input, $i, $end - $i + 1);
            $i = $end + 1;
            continue;
        }
        if ($c === '{' && $input[$i + 1] === '!') {
            // Local params block: consume to the matching '}'.
            $depth = 0;
            $j = $i;
            for (; $j < $len; $j++) {
                if ($input[$j] === '{') {
                    $depth++;
                } elseif ($input[$j] === '}') {
                    $depth--;
                    if ($depth === 0) {
                        break;
                    }
                }
            }
            $tokens[] = substr($input, $i, $j - $i + 1);
            $i = $j + 1;
            continue;
        }
        // Bare word: consume until whitespace or a structural char.
        $j = $i;
        while ($j < $len && !ctype_space($input[$j]) && !dlf_solr_in_list($input[$j], ['(', ')', '[', ']', '"'])) {
            $j++;
        }
        $tokens[] = substr($input, $i, $j - $i);
        $i = $j;
    }
    return $tokens;
}

function dlf_solr_in_list(string $needle, array $haystack): bool
{
    return in_array($needle, $haystack, true);
}

/**
 * Parse a boolean expression from a token stream (AND / OR / NOT / ANDNOT,
 * parenthesized groups, optional leading '-' negation). Returns a node.
 */
function dlf_solr_parse_expr(array $tokens, int &$pos, bool $expectClose): ?array
{
    $left = dlf_solr_parse_atom($tokens, $pos);
    while ($pos < count($tokens)) {
        $upper = strtoupper($tokens[$pos]);
        if ($upper === 'AND' || $upper === 'OR' || $upper === 'NOT' || $upper === 'ANDNOT') {
            $op = $upper;
            $pos++;
            $right = dlf_solr_parse_atom($tokens, $pos);
            $left = ['op' => $op, 'left' => $left, 'right' => $right];
            continue;
        }
        break;
    }
    return $left;
}

/**
 * Parse a single atom: a parenthesized group or a field/value/range/bareword
 * term (with optional leading '-' negation).
 */
function dlf_solr_parse_atom(array $tokens, int &$pos): ?array
{
    if ($pos >= count($tokens)) {
        return null;
    }
    $tok = $tokens[$pos];

    // A field term may be negated by a leading '-' (e.g. "-type:page"), where
    // the '-' is part of the same bare-word token. Strip it and mark negation.
    $negated = false;
    if ($tok !== '-' && str_starts_with($tok, '-') && str_contains(substr($tok, 1), ':')) {
        $negated = true;
        $tok = substr($tok, 1);
    }

    // A local-params block may lead a field query (e.g. {!join ...}field:...).
    $innerParams = null;
    if (str_starts_with($tok, '{!')) {
        $close = strpos($tok, '}');
        $innerParams = $close !== false ? substr($tok, 2, $close - 2) : substr($tok, 2);
        $remainder = $close !== false ? substr($tok, $close + 1) : '';
        if ($remainder !== '') {
            // The rest of the term is attached to the same token.
            $tok = $remainder;
        } else {
            // The remainder is the following token(s); re-parse as a term.
            if ($pos < count($tokens)) {
                $pos++;
                if ($pos >= count($tokens)) {
                    return ['type' => 'neg', 'expr' => ['type' => 'const', 'value' => true], 'inner' => $innerParams];
                }
                $tok = $tokens[$pos];
            } else {
                return ['type' => 'neg', 'expr' => ['type' => 'const', 'value' => true], 'inner' => $innerParams];
            }
        }
    }

    if ($tok === '(') {
        $pos++;
        $node = dlf_solr_parse_expr($tokens, $pos, true);
        if ($pos < count($tokens) && $tokens[$pos] === ')') {
            $pos++;
        }
        return $negated ? ['type' => 'neg', 'expr' => $node] : $node;
    }

    $pos++; // consume the term token

    // Range: [a TO b] / {a TO b}. May be split across tokens as "[ a TO b ]".
    if ($tok === '[' || $tok === '{' || $tok === ']') {
        return ['type' => 'range', 'raw' => dlf_solr_collect_range($tokens, $pos, $tok), 'inner' => $innerParams, 'negated' => $negated];
    }

    // Field query: field:value or field:(...) or field:[...].
    if (str_contains($tok, ':')) {
        [$field, $valuePart] = explode(':', $tok, 2);
        $valuePart = $valuePart === '' ? '' : $valuePart;
        // valuePart may be the start of a "(" group or a quoted value.
        if ($valuePart === '(' || $valuePart === '') {
            // Gather a parenthesized value group: ( "a" OR "b" ... )
            $value = dlf_solr_collect_value_group($tokens, $pos, $valuePart);
        } else {
            $value = dlf_solr_unquote($valuePart);
        }
        return [
            'type' => 'field',
            'field' => $field,
            'value' => $value,
            'inner' => $innerParams,
            'negated' => $negated,
        ];
    }

    // Bare word: match across the text-ish fields.
    return ['type' => 'bare', 'value' => $tok, 'negated' => $negated];
}

/**
 * Collect a parenthesized value group like ( "a" OR "b" ) starting after the
 * field token (valuePart is "(" or empty and "(" follows). Returns a list of
 * quoted/raw value strings joined by the (ignored, treated as OR) operators.
 *
 * @return array<int, string>
 */
function dlf_solr_collect_value_group(array $tokens, int &$pos, string $valuePart): array
{
    $values = [];
    if ($valuePart === '(') {
        $pos++; // consume the "(" already consumed as valuePart? It is part of the token, not a separate token.
    }
    // If the opening paren was a separate token, consume it.
    if ($pos < count($tokens) && $tokens[$pos] === '(') {
        $pos++;
    }
    while ($pos < count($tokens)) {
        $t = $tokens[$pos];
        if ($t === ')') {
            $pos++;
            break;
        }
        if (strtoupper($t) === 'OR' || strtoupper($t) === 'AND' || strtoupper($t) === 'NOT') {
            $pos++;
            continue;
        }
        $values[] = dlf_solr_unquote($t);
        $pos++;
    }
    return $values;
}

/**
 * Collect a range expression that may be split across the current token and
 * following tokens. Reassembles to "[a TO b]" (or "{a TO b}").
 */
function dlf_solr_collect_range(array $tokens, int &$pos, string $first): string
{
    $parts = [$first];
    while ($pos < count($tokens) && count($parts) < 5) {
        $t = $tokens[$pos];
        if ($t === ']') {
            $parts[] = ']';
            $pos++;
            break;
        }
        $parts[] = $t;
        $pos++;
    }
    return implode(' ', $parts);
}

function dlf_solr_unquote(string $value): string
{
    $value = trim($value);
    if (strlen($value) >= 2 && $value[0] === '"' && $value[strlen($value) - 1] === '"') {
        return substr($value, 1, -1);
    }
    return $value;
}

/**
 * Evaluate a parsed node against a document.
 */
function dlf_solr_eval(?array $node, array $doc): bool
{
    if ($node === null) {
        return true;
    }
    // Boolean operator nodes carry an "op" key (AND / OR / NOT / ANDNOT).
    if (isset($node['op'])) {
        $op = $node['op'];
        if ($op === 'AND') {
            return dlf_solr_eval($node['left'], $doc) && dlf_solr_eval($node['right'], $doc);
        }
        if ($op === 'OR') {
            return dlf_solr_eval($node['left'], $doc) || dlf_solr_eval($node['right'], $doc);
        }
        if ($op === 'NOT' || $op === 'ANDNOT') {
            return !dlf_solr_eval($node['right'] ?? $node['left'], $doc);
        }
        return true;
    }
    switch ($node['type'] ?? '') {
        case 'const':
            return (bool) $node['value'];
        case 'neg':
            return !dlf_solr_eval($node['expr'], $doc);
        case 'field':
            return dlf_solr_eval_field($node, $doc);
        case 'range':
            return dlf_solr_eval_range($node, $doc);
        case 'bare':
            return dlf_solr_eval_bare($node, $doc);
        default:
            return true;
    }
}

function dlf_solr_eval_field(array $node, array $doc): bool
{
    $field = $node['field'];
    $inner = $node['inner'] ?? '';
    // Handle {!join from=X to=Y}field:... as a self-join (from == to) or a
    // relationship join. For the demo's date-range join (from=uid to=uid) this
    // is effectively just field:value on the same doc.
    if (preg_match('/join\s+from=([^ }]+)\s+to=([^ }]+)/', $inner, $m)) {
        if ($m[1] !== $m[2]) {
            // Relationship join is not approximated for a single doc; treat as
            // matching the field value on the doc itself (best-effort).
        }
    }
    $value = $node['value'];
    $negated = (bool) ($node['negated'] ?? false);
    $ok = dlf_solr_field_query($field, $value, $doc);
    return $negated ? !$ok : $ok;
}

/**
 * Field query semantics. value is either a scalar string or a list of strings
 * (from a "(a OR b)" group). A match is: any doc value equals a requested
 * value, or (for a scalar) is a substring of a doc value. Multi-valued doc
 * fields match if any element matches.
 */
function dlf_solr_field_query(string $field, $value, array $doc): bool
{
    if (!array_key_exists($field, $doc)) {
        return false;
    }
    $docValues = $doc[$field];
    $docValues = is_array($docValues) ? $docValues : [$docValues];

    $wanted = is_array($value) ? $value : [$value];
    foreach ($wanted as $w) {
        $w = dlf_solr_unquote((string) $w);
        // Wildcard / all.
        if ($w === '' || $w === '*') {
            return true;
        }
        $wLower = mb_strtolower($w);
        foreach ($docValues as $dv) {
            if ($dv === null) {
                continue;
            }
            // Boolean fields: Solr writes true/false; PHP bools stringify to 1/0.
            if (is_bool($dv)) {
                if (($wLower === 'true' && $dv) || ($wLower === 'false' && !$dv)) {
                    return true;
                }
                continue;
            }
            $dv = (string) $dv;
            if ($dv === $w || mb_strtolower($dv) === $wLower) {
                return true;
            }
            // Case-insensitive token containment (approximates edismax on
            // tokenized fields) for multi-word or free-text-ish values.
            if (mb_stripos($dv, $w) !== false) {
                return true;
            }
        }
    }
    return false;
}

function dlf_solr_eval_range(array $node, array $doc): bool
{
    $negated = (bool) ($node['negated'] ?? false);
    $raw = (string) $node['raw'];
    // Pull out the field before the opening bracket.
    if (!preg_match('/^(\w+)\s*\[/', $raw, $m)) {
        return true; // unparseable -> do not exclude
    }
    $field = $m[1];
    if (!array_key_exists($field, $doc)) {
        return !$negated;
    }
    // Extract [a TO b]
    if (preg_match('/\[\s*(.*?)\s+TO\s+(.*?)\s*\]/i', $raw, $r) === 0) {
        return !$negated;
    }
    $lo = trim($r[1], ' "');
    $hi = trim($r[2], ' "');
    $docValues = $doc[$field];
    $docValues = is_array($docValues) ? $docValues : [$docValues];
    foreach ($docValues as $dv) {
        if ($dv === null || $dv === '') {
            continue;
        }
        $dv = (string) $dv;
        $ok = true;
        if ($lo !== '' && $dv < $lo) {
            $ok = false;
        }
        if ($hi !== '' && $dv > $hi) {
            $ok = false;
        }
        if ($ok) {
            return !$negated;
        }
    }
    return $negated;
}

function dlf_solr_eval_bare(array $node, array $doc): bool
{
    $negated = (bool) ($node['negated'] ?? false);
    $w = dlf_solr_unquote((string) $node['value']);
    if ($w === '' || $w === '*') {
        return !$negated;
    }
    // Match against title, structure_path and every *_usi / *_faceting /
    // *_sorting field (the tokenized/indexed metadata fields).
    foreach ($doc as $field => $value) {
        if (dlf_solr_in_list($field, ['title', 'structure_path']) || preg_match('/_(usi|faceting|sorting|tsi)$/', $field)) {
            if (dlf_solr_field_query($field, [$w], $doc)) {
                return !$negated;
            }
        }
    }
    // Fall back to a scan of all scalar string values.
    foreach ($doc as $value) {
        if (is_array($value)) {
            $value = reset($value);
        }
        if (is_string($value) && mb_stripos($value, $w) !== false) {
            return !$negated;
        }
    }
    return $negated;
}

/**
 * Build a demo catalog from the dlf test fixtures, rewriting each document's
 * "id" to "<uid><xmlId>"-style and adding the collection_faceting mirror. This
 * is used by the setup script / standalone tests, not by the request handler.
 *
 * @return array<int, array<string,mixed>>
 */
function dlf_solr_build_catalog(array $fixtureDocs): array
{
    $out = [];
    foreach ($fixtureDocs as $doc) {
        if (!is_array($doc)) {
            continue;
        }
        $uid = (string) ($doc['uid'] ?? 'doc');
        $sid = (string) ($doc['sid'] ?? 'ROOT');
        $doc['id'] = $uid . $sid;
        if (!empty($doc['collection']) && empty($doc['collection_faceting'])) {
            $doc['collection_faceting'] = is_array($doc['collection']) ? $doc['collection'] : [$doc['collection']];
        }
        $out[] = $doc;
    }
    return $out;
}
