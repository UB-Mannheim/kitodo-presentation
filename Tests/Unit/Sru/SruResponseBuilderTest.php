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

namespace Kitodo\Dlf\Tests\Unit\Sru;

use Kitodo\Dlf\Sru\SruResponseBuilder;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;

/**
 * Test case for the class "SruResponseBuilder".
 *
 * @access public
 */
class SruResponseBuilderTest extends TestCase
{
    /**
     * @var SruResponseBuilder
     */
    protected SruResponseBuilder $subject;

    /**
     * Sets up the fixture.
     */
    protected function setUp(): void
    {
        parent::setUp();
        $this->subject = new SruResponseBuilder();
    }

    /**
     * The XML must use the literal `srw:` prefix (not a default namespace),
     * because the DFG-Viewer client resolves the response with
     * `xpath('/srw:searchRetrieveResponse')` without registering a prefix.
     */
    #[Test]
    public function buildResponseUsesSrwPrefix(): void
    {
        $xml = $this->subject->buildResponse([$this->record(['page' => 3])]);
        $this->assertStringContainsString(
            '<srw:searchRetrieveResponse xmlns:srw="http://www.loc.gov/zing/srw/"',
            $xml
        );
    }

    /**
     * The XML must be well-formed and parse like the DFG-Viewer client does.
     */
    #[Test]
    public function buildResponseParsesWithClientAccessors(): void
    {
        $xml = $this->subject->buildResponse([
            $this->record([
                'page' => 3,
                'width' => 2481,
                'height' => 3508,
                'parentUrl' => 'https://host/mets.xml',
                'hits' => [
                    [
                        'x1' => 100,
                        'y1' => 200,
                        'x2' => 500,
                        'y2' => 240,
                        'text' => [
                            ['text' => 'context ', 'highlight' => false],
                            ['text' => 'term', 'highlight' => true],
                            ['text' => ' context', 'highlight' => false],
                        ],
                    ]
                ],
            ])
        ]);
        $sru = simplexml_load_string($xml);
        $this->assertNotFalse($sru);

        // The client's exact accessors:
        $response = $sru->xpath('/srw:searchRetrieveResponse');
        $this->assertNotFalse($response);
        $records = $sru->xpath('/srw:searchRetrieveResponse/srw:records/srw:record');
        $this->assertCount(1, $records);
        $recordData = $records[0]->xpath('//srw:recordData');
        $this->assertCount(1, $recordData);
        $page = $recordData[0]->children('http://dfg-viewer.de/')->page;

        $this->assertSame('3', (string) $page->attributes()->id);
        $this->assertSame('2481', (string) $page->attributes()->width);
        $this->assertSame('3508', (string) $page->attributes()->height);
        $this->assertSame('https://host/mets.xml', (string) $page->parent->attributes()->url);

        $this->assertCount(1, $page->fulltexthit);
        $hit = $page->fulltexthit[0];
        $this->assertSame('100', (string) $hit->attributes()->x1);
        $this->assertSame('200', (string) $hit->attributes()->y1);
        $this->assertSame('500', (string) $hit->attributes()->x2);
        $this->assertSame('240', (string) $hit->attributes()->y2);
        $this->assertNotEmpty($hit->span);
    }

    /**
     * Page dimensions must be omitted when not available (e.g. no ALTO/OCR).
     */
    #[Test]
    public function buildResponseOmitsMissingDimensions(): void
    {
        $xml = $this->subject->buildResponse([$this->record(['page' => 7])]);
        $sru = simplexml_load_string($xml);
        $recordData = $sru->xpath('/srw:searchRetrieveResponse/srw:records/srw:record/srw:recordData');
        $page = $recordData[0]->children('http://dfg-viewer.de/')->page;
        $attributes = $page->attributes();
        $this->assertSame('7', (string) $attributes->id);
        $this->assertFalse(isset($attributes->width));
        $this->assertFalse(isset($attributes->height));
    }

    /**
     * A record without hits must not emit any fulltexthit element.
     */
    #[Test]
    public function buildResponseWithoutHits(): void
    {
        $xml = $this->subject->buildResponse([$this->record(['page' => 2, 'hits' => []])]);
        $sru = simplexml_load_string($xml);
        $this->assertNotFalse($sru);
        $page = $sru->xpath('/srw:searchRetrieveResponse/srw:records/srw:record/srw:recordData')
            [0]->children('http://dfg-viewer.de/')->page;
        $this->assertCount(0, $page->fulltexthit);
    }

    /**
     * XML special characters must be escaped in attributes and text.
     */
    #[Test]
    public function buildResponseEscapesSpecialCharacters(): void
    {
        $xml = $this->subject->buildResponse([
            $this->record([
                'page' => 1,
                'parentUrl' => 'https://host/mets.xml?x=1&y="2"<z>',
                'hits' => [
                    [
                        'x1' => 1,
                        'y1' => 2,
                        'x2' => 3,
                        'y2' => 4,
                        'text' => [['text' => 'a < b & "c" > d', 'highlight' => true]],
                    ]
                ],
            ])
        ]);
        $this->assertStringContainsString(
            'url="https://host/mets.xml?x=1&amp;y=&quot;2&quot;&lt;z&gt;"',
            $xml
        );
        $this->assertStringContainsString(
            '<span class="highlight">a &lt; b &amp; &quot;c&quot; &gt; d</span>',
            $xml
        );
        // The document must remain well-formed.
        $this->assertNotFalse(simplexml_load_string($xml));
    }

    /**
     * Multiple hits per record and multiple records must all be emitted.
     */
    #[Test]
    public function buildResponseWithMultipleHitsAndRecords(): void
    {
        $xml = $this->subject->buildResponse([
            $this->record([
                'page' => 1,
                'hits' => [
                    ['x1' => 1, 'y1' => 2, 'x2' => 3, 'y2' => 4],
                    ['x1' => 5, 'y1' => 6, 'x2' => 7, 'y2' => 8],
                ],
            ]),
            $this->record(['page' => 2, 'hits' => [['x1' => 9, 'y1' => 10, 'x2' => 11, 'y2' => 12]]]),
        ]);
        $sru = simplexml_load_string($xml);
        $this->assertCount(2, $sru->xpath('/srw:searchRetrieveResponse/srw:records/srw:record'));
        $recordData = $sru->xpath('/srw:searchRetrieveResponse/srw:records/srw:record/srw:recordData');
        $pages = array_map(
            static fn ($data) => $data->children('http://dfg-viewer.de/')->page,
            $recordData
        );
        $this->assertCount(2, $pages);
        $this->assertCount(2, $pages[0]->fulltexthit);
        $this->assertCount(1, $pages[1]->fulltexthit);
        $this->assertStringContainsString('<srw:numberOfRecords>2</srw:numberOfRecords>', $xml);
    }

    /**
     * Build a record array with defaults.
     *
     * @param array<string, mixed> $overrides
     * @return array<string, mixed>
     */
    private function record(array $overrides = []): array
    {
        return array_merge([
            'page' => 1,
            'parentUrl' => 'https://host/mets.xml',
            'hits' => [],
        ], $overrides);
    }
}
