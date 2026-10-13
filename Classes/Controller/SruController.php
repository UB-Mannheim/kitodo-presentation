<?php

/**
 * (c) Kitodo. Key to digital objects e.V. <contact@kitodo.org>
 *
 * This file is part of the Kitodo and TYPO3 projects.
 *
 * @license GNU General Public License version 3 or later.
 * For the full copyright and license information, please read the
 * LICENSE.txt file that was distributed with this source code.
 */

namespace Kitodo\Dlf\Controller;

use Kitodo\Dlf\Common\Solr\Solr;
use Kitodo\Dlf\Common\Solr\SearchResult\ResultDocument;
use Kitodo\Dlf\Sru\SruResponseBuilder;
use Psr\Http\Message\ResponseInterface;
use Solarium\Core\Query\Result\ResultInterface;
use TYPO3\CMS\Core\Utility\GeneralUtility;

/**
 * Controller class for the plugin 'SRU Interface'.
 *
 * Serves the DFG-Viewer SRU client: fulltext hits over an SRU 1.2
 * "searchRetrieve" request in the "dfg-viewer/page" record schema, so a
 * DFG-Viewer installation can search another repository's Solr index and
 * deep-link (with highlight boxes) into this repository's PageView viewer.
 *
 * @package TYPO3
 * @subpackage dlf
 *
 * @access public
 */
class SruController extends AbstractController
{
    /**
     * The record schema served by this plugin.
     *
     * @access private
     * @var string
     */
    private const RECORD_SCHEMA = 'dfg-viewer/page';

    /**
     * The hard cap for a single response's record count.
     *
     * @access private
     * @var int
     */
    private const MAX_RECORD_CAP = 100;

    /**
     * The marker tags used for highlighted snippets. Set explicitly in the
     * Solr request (see executeSolrQuery()) so the snippet text can be split
     * deterministically.
     *
     * @access private
     * @var string
     */
    private const HIGHLIGHT_OPEN = '<em>';

    /**
     * The closing marker tag for highlighted snippets.
     *
     * @access private
     * @var string
     */
    private const HIGHLIGHT_CLOSE = '</em>';

    /**
     * Initializes the current action.
     *
     * @access public
     *
     * @return void
     */
    public function initializeAction(): void
    {
        // Force the "xml" format so Extbase does not try to render an
        // "xml" subformat template for the "main" action.
        $this->request = $this->request->withFormat('xml');
    }

    /**
     * The main method of the plugin.
     *
     * Handles a single "searchRetrieve" request and returns the full SRU
     * "searchRetrieveResponse" XML document. All other requests are answered
     * with an empty (but valid) record list.
     *
     * @access public
     *
     * @return ResponseInterface
     */
    public function mainAction(): ResponseInterface
    {
        $queryParams = $this->request->getQueryParams();
        $operation = (string) ($queryParams['operation'] ?? '');
        $recordSchema = (string) ($queryParams['recordSchema'] ?? self::RECORD_SCHEMA);

        $records = [];
        if ($operation === 'searchRetrieve' && $recordSchema === self::RECORD_SCHEMA) {
            $query = (string) ($queryParams['query'] ?? '');
            if ($query !== '') {
                $startRecord = max(1, (int) ($queryParams['startRecord'] ?? 1));
                $maximumRecords = (int) ($queryParams['maximumRecords'] ?? 0);

                // Sanitize FlexForm settings (e.g. default for maximumRecords).
                $this->sanitizeSettings();
                if ($maximumRecords <= 0) {
                    $maximumRecords = (int) $this->settings['maximumRecords'];
                }
                $maximumRecords = min($maximumRecords, self::MAX_RECORD_CAP);

                $solr = $this->getSolr();
                if ($solr) {
                    $records = $this->getRecords($solr, $query, $startRecord - 1, $maximumRecords);
                }
            }
        }

        // The static TypoScript of the plugin (disableAllHeaderCode and a
        // Content-Type: text/xml header) delivers this body as a pure XML
        // document.
        $builder = GeneralUtility::makeInstance(SruResponseBuilder::class);
        return $this->htmlResponse($builder->buildResponse($records));
    }

    /**
     * Executes the fulltext query on the Solr core and converts the result
     * into SRU records, one per hit physical page.
     *
     * @access protected
     *
     * @param Solr $solr The Solr instance to query
     * @param string $query The (already validated) search term
     * @param int $start Zero-based offset of the first record
     * @param int $rows Maximum number of records
     *
     * @return array<int, array<string, mixed>> The SRU records
     */
    protected function getRecords(Solr $solr, string $query, int $start, int $rows): array
    {
        $records = [];
        $fields = Solr::getFields();

        try {
            $result = $this->executeSolrQuery($solr, $query, $start, $rows);
        } catch (\Exception $error) {
            $this->logger->error('SRU search failed: ' . $error->getMessage());
            return $records;
        }

        $highlighting = $result->getData()['ocrHighlighting'] ?? [];

        // @phpstan-ignore-next-line
        foreach ($result as $record) {
            $resultDocument = new ResultDocument($record, $highlighting, $fields);
            $page = $resultDocument->getPage();
            $location = (string) ($record[$fields['location']] ?? '');
            if ($page === null || $location === '') {
                continue;
            }

            $sruRecord = [
                'page' => $page,
                'parentUrl' => $location,
                'hits' => [],
            ];
            // The page width/height from the OCR highlighting response are in
            // the same coordinate frame as the highlight boxes (the ALTO
            // imageWidth/imageHeight) and are only present if the page has
            // OCR data. Omit the attributes otherwise.
            $pages = $resultDocument->getPages();
            if (!empty($pages)) {
                $sruRecord['width'] = $pages[0]->getWidth();
                $sruRecord['height'] = $pages[0]->getHeight();
            }

            $segments = $this->parseSnippetSegments($resultDocument->getSnippets());
            $preview = (string) ($record[$fields['thumbnail']] ?? '');

            foreach ($resultDocument->getHighlights() as $highlight) {
                $hit = [
                    'x1' => $highlight->getXBeginPosition(),
                    'y1' => $highlight->getYBeginPosition(),
                    'x2' => $highlight->getXEndPosition(),
                    'y2' => $highlight->getYEndPosition(),
                    'text' => $segments,
                ];
                if ($preview !== '') {
                    $hit['preview'] = $preview;
                }
                $sruRecord['hits'][] = $hit;
            }

            if (!empty($sruRecord['hits'])) {
                $records[] = $sruRecord;
            }
        }

        return $records;
    }

    /**
     * Executes the Solr query with OCR highlighting.
     *
     * Unlike the in-document search, the query is not restricted to a single
     * document UID: the whole configured core is searched, and each hit
     * document is one physical page (fulltext is stored on page level).
     *
     * @access private
     *
     * @param Solr $solr The Solr instance to query
     * @param string $query The (already validated) search term
     * @param int $start Zero-based offset of the first record
     * @param int $rows Maximum number of records
     *
     * @return ResultInterface The Solr result
     */
    private function executeSolrQuery(Solr $solr, string $query, int $start, int $rows): ResultInterface
    {
        $fields = Solr::getFields();
        $select = $solr->service->createSelect();
        $select->setFields([
            $fields['id'],
            $fields['uid'],
            $fields['page'],
            $fields['location'],
            $fields['thumbnail'],
        ]);
        $select->setQuery($fields['fulltext'] . ':(' . Solr::escapeQuery($query) . ')');
        $select->setStart($start)->setRows($rows);
        $select->getHighlighting();
        $solrRequest = $solr->service->createRequest($select);

        // It is necessary to add the custom parameters to the request
        // because the query object doesn't allow custom parameters.
        // Field for which highlighting is going to be performed,
        // is required if you want to have OCR highlighting
        $solrRequest->addParam('hl.ocr.fl', $fields['fulltext']);
        // Return the coordinates of the highlighted search as absolute coordinates
        $solrRequest->addParam('hl.ocr.absoluteHighlights', 'on');
        // Max amount of snippets for a single page
        $solrRequest->addParam('hl.snippets', '40');
        // The fulltext is stored on page level, but the page dimensions
        // (imageWidth/imageHeight) are needed for the page record
        $solrRequest->addParam('hl.ocr.trackPages', 'on');
        // Set the highlight tags explicitly so the snippet text can be split
        // deterministically (Solr's default is <em> as well)
        $solrRequest->addParam('hl.tag.pre', self::HIGHLIGHT_OPEN);
        $solrRequest->addParam('hl.tag.post', self::HIGHLIGHT_CLOSE);
        $solrRequest->addParam('hl.ocr.tag.pre', self::HIGHLIGHT_OPEN);
        $solrRequest->addParam('hl.ocr.tag.post', self::HIGHLIGHT_CLOSE);

        $response = $solr->service->executeRequest($solrRequest);
        return $solr->service->createResult($select, $response);
    }

    /**
     * Splits a highlighted snippet string into plain and highlighted segments.
     *
     * @access private
     *
     * @param string $snippet The snippet text with highlight marker tags
     *
     * @return array<int, array{text: string, highlight: bool}> The segments,
     *         each with "text" (string) and "highlight" (bool)
     */
    private function parseSnippetSegments(string $snippet): array
    {
        $segments = [];
        if ($snippet === '') {
            return $segments;
        }
        $parts = preg_split(
            '/' . preg_quote(self::HIGHLIGHT_OPEN, '/') . '|' . preg_quote(self::HIGHLIGHT_CLOSE, '/') . '/',
            $snippet
        );
        if ($parts === false) {
            return $segments;
        }
        $highlighted = false;
        foreach ($parts as $part) {
            $text = trim($part);
            if ($text === '') {
                continue;
            }
            $segments[] = ['text' => (string) $text, 'highlight' => $highlighted];
            $highlighted = !$highlighted;
        }
        return $segments;
    }
}
