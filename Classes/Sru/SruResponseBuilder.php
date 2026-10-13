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

namespace Kitodo\Dlf\Sru;

/**
 * Builds an SRU 1.2 "searchRetrieveResponse" document in the "dfg-viewer/page"
 * record schema, as consumed by the DFG-Viewer SRU client (see
 * Classes/Middleware/SruMiddleware.php in the "slub/dfg-viewer" extension).
 *
 * The response is deliberately emitted with the **literal `srw:` prefix**
 * (`xmlns:srw="http://www.loc.gov/zing/srw/"`) rather than the standard
 * default namespace, because the client resolves the response with
 * `xpath('/srw:searchRetrieveResponse')` without registering any prefix. A
 * default-namespace root (as returned by standard SRU servers) would not
 * match that query.
 *
 * Each record's `<recordData>` contains a `<page>` element in the
 * "http://dfg-viewer.de/" namespace carrying the hit page's number and
 * (when known) its image width/height, plus one `<fulltexthit>` element per
 * OCR hit with absolute coordinates and a `<span>` snippet.
 *
 * @access public
 */
class SruResponseBuilder
{
    /**
     * The SRW (SRU over the Web) namespace.
     *
     * @access private
     * @var string
     */
    private const SRW_NAMESPACE = 'http://www.loc.gov/zing/srw/';

    /**
     * The DFG-Viewer record-data namespace.
     *
     * @access private
     * @var string
     */
    private const DFGVIEWER_NAMESPACE = 'http://dfg-viewer.de/';

    /**
     * Escape a value for use as XML text content.
     *
     * @access public
     *
     * @param string $value The value to escape
     *
     * @return string The escaped value
     */
    public static function escapeText(string $value): string
    {
        return htmlspecialchars($value, ENT_QUOTES | ENT_XML1, 'UTF-8', false);
    }

    /**
     * Escape a value for use as an XML attribute value.
     *
     * @access public
     *
     * @param string $value The value to escape
     *
     * @return string The escaped value
     */
    public static function escapeAttribute(string $value): string
    {
        return htmlspecialchars($value, ENT_QUOTES | ENT_XML1, 'UTF-8', false);
    }

    /**
     * Build the complete SRU "searchRetrieveResponse" XML document.
     *
     * @access public
     *
     * @param array<int, array<string, mixed>> $records The records to emit, each with
     *        the keys "page" (int), "width" (int, optional), "height" (int, optional),
     *        "parentUrl" (string) and "hits" (array of hit arrays, see buildRecord())
     *        "numberRecords" (int, optional, defaults to count($records))
     *
     * @return string The complete XML document
     */
    public function buildResponse(array $records): string
    {
        $recordsXml = '';
        foreach ($records as $record) {
            $recordsXml .= $this->buildRecord($record);
        }
        return '<?xml version="1.0" encoding="UTF-8"?>' . "\n"
            . '<srw:searchRetrieveResponse xmlns:srw="' . self::SRW_NAMESPACE . '" version="1.2">'
            . '<srw:version>1.2</srw:version>'
            . '<srw:numberOfRecords>' . count($records) . '</srw:numberOfRecords>'
            . '<srw:records>' . $recordsXml . '</srw:records>'
            . '</srw:searchRetrieveResponse>';
    }

    /**
     * Build a single `<srw:record>` element.
     *
     * @access protected
     *
     * @param array<string, mixed> $record The record with keys "page" (int),
     *        "width" (int, optional), "height" (int, optional), "parentUrl" (string)
     *        and "hits" (array<int, array<string, mixed>>), each hit having
     *        "x1" (int), "y1" (int), "x2" (int), "y2" (int), "preview" (string,
     *        optional) and "text" (array<int, array<string, string>>, optional),
     *        where each text segment has "text" (string) and "highlight" (bool)
     *
     * @return string The record XML
     */
    protected function buildRecord(array $record): string
    {
        $pageAttributes = 'id="' . self::escapeAttribute((string) $record['page']) . '"';
        if (isset($record['width'])) {
            $pageAttributes .= ' width="' . self::escapeAttribute((string) $record['width']) . '"';
        }
        if (isset($record['height'])) {
            $pageAttributes .= ' height="' . self::escapeAttribute((string) $record['height']) . '"';
        }
        $hitsXml = '';
        foreach ($record['hits'] as $hit) {
            $hitsXml .= $this->buildFulltextHit($hit);
        }
        return '<srw:record>'
            . '<srw:recordSchema>dfg-viewer/page</srw:recordSchema>'
            . '<srw:recordPacking>xml</srw:recordPacking>'
            . '<srw:recordData>'
            . '<page xmlns="' . self::DFGVIEWER_NAMESPACE . '" ' . $pageAttributes . '>'
            . '<parent url="' . self::escapeAttribute((string) $record['parentUrl']) . '"/>'
            . $hitsXml
            . '</page>'
            . '</srw:recordData>'
            . '</srw:record>';
    }

    /**
     * Build a single `<fulltexthit>` element with its `<span>` snippet.
     *
     * @access protected
     *
     * @param array<string, mixed> $hit The hit with keys "x1" (int), "y1" (int),
     *        "x2" (int), "y2" (int), "preview" (string, optional) and "text"
     *        (array<int, array<string, string>>, optional), where each text
     *        segment has "text" (string) and "highlight" (bool)
     *
     * @return string The fulltexthit XML
     */
    protected function buildFulltextHit(array $hit): string
    {
        $attributes = 'x1="' . self::escapeAttribute((string) $hit['x1']) . '"';
        $attributes .= ' y1="' . self::escapeAttribute((string) $hit['y1']) . '"';
        $attributes .= ' x2="' . self::escapeAttribute((string) $hit['x2']) . '"';
        $attributes .= ' y2="' . self::escapeAttribute((string) $hit['y2']) . '"';
        if (!empty($hit['preview'])) {
            $attributes .= ' preview="' . self::escapeAttribute((string) $hit['preview']) . '"';
        }
        return '<fulltexthit ' . $attributes . '>'
            . $this->buildSpan((array) ($hit['text'] ?? []))
            . '</fulltexthit>';
    }

    /**
     * Build the `<span>` snippet element.
     *
     * The snippet is emitted as **inline mixed content**: context text is written
     * as direct text of the outer `<span>`, and matched segments are wrapped in a
     * `<span class="highlight">` child element. This is the DFG-Viewer snippet
     * format, e.g.
     * `<span>some context <span class="highlight">term</span> more context</span>`.
     *
     * This structure is chosen so the snippet survives both the current and a
     * future DFG-Viewer client. The current client reads the outer span's direct
     * text (so the context shows), while a client fixed to iterate child elements
     * (see "slub/dfg-viewer/AGENTS.md") would read the `<span class="highlight">`
     * children (so the matched word shows). Emitting only per-segment `<span>`
     * children would render empty on the current client and make hits invisible
     * in the results list.
     *
     * @access protected
     *
     * @param array<int, array<string, string>> $segments The text segments, each with
     *        "text" (string) and "highlight" (bool)
     *
     * @return string The span XML
     */
    protected function buildSpan(array $segments): string
    {
        if (empty($segments)) {
            return '';
        }
        $spanXml = '<span>';
        foreach ($segments as $segment) {
            $text = self::escapeText((string) ($segment['text'] ?? ''));
            if (!empty($segment['highlight'])) {
                $spanXml .= '<span class="highlight">' . $text . '</span>';
            } else {
                $spanXml .= $text;
            }
        }
        return $spanXml . '</span>';
    }
}
