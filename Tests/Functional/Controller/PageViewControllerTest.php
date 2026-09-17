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

namespace Kitodo\Dlf\Tests\Functional\Controller;

use Kitodo\Dlf\Controller\PageViewController;
use PHPUnit\Framework\Attributes\Test;

class PageViewControllerTest extends AbstractControllerTestCase
{
    private static array $databaseFixtures = [
        __DIR__ . '/../../Fixtures/Controller/documents_local.csv',
        __DIR__ . '/../../Fixtures/Controller/pages.csv',
        __DIR__ . '/../../Fixtures/Controller/solrcores.csv'
    ];

    public function setUp(): void
    {
        parent::setUp();
        $this->setUpData(self::$databaseFixtures);
    }

    /**
     * This test hard-codes the URL that is used to load the METS of document 2001 (see documents_local.csv).
     * It will fail unless the docker test environment is used with the proxy hosted at "web:8001".
     */
    #[Test]
    public function canMainAction()
    {
        $settings = [
            'storagePid' => self::$storagePid,
            'solrcore' => self::$solrCoreId
        ];

        $templateHtml = '<html>
                docId:{docId}
                page:{page}
                images:<f:for each="{images}" as="image">
                    {image.url}
                    {image.mimetype}</f:for>
                viewerConfiguration:<f:format.raw>{viewerConfiguration}</f:format.raw>
            </html>';
        $controller = $this->setUpController(PageViewController::class, $settings, $templateHtml);
        $request = $this->setUpRequest('main', ['tx_dlf' => [ 'id' => 2001, 'page' => 2 ] ]);

        $response = $controller->processRequest($request);

        $response->getBody()->rewind();
        $actual = $response->getBody()->getContents();
        $expected = '<html>
                docId:2001
                page:2
                images:
                    http://example.com/mets_audio/jpegs/00000002.tif.large.jpg
                    image/jpeg
                viewerConfiguration:$(document).ready(function() {
                    if (dlfUtils.exists(dlfViewer)) {
                        tx_dlf_viewer = new dlfViewer({"controls":[""],"div":"tx-dlf-map","progressElementId":"tx-dlf-page-progress","images":[{"url":"http:\/\/example.com\/mets_audio\/jpegs\/00000002.tif.large.jpg","mimetype":"image\/jpeg"}],"fulltexts":[[]],"score":[],"annotationContainers":[[]],"measureCoords":[],"useInternalProxy":0,"verovioAnnotations":[],"currentMeasureId":"","measureIdToIndex":[]});
                    }
                });
            </html>';
        $this->assertEquals($expected, $actual);
    }

    /**
     * A document id that cannot be resolved to a readable document (e.g. a document URL that
     * does not point to a readable document, or an unknown uid) must result in an HTTP 404 and
     * set the "documentNotFound" flag so the template shows a localized message instead of the
     * empty viewer.
     */
    #[Test]
    public function returnsNotFoundForMissingDocument()
    {
        $settings = [
            'storagePid' => self::$storagePid,
            'solrcore' => self::$solrCoreId
        ];

        $templateHtml = '<html>notFound:{documentNotFound}</html>';
        $controller = $this->setUpController(PageViewController::class, $settings, $templateHtml);
        $request = $this->setUpRequest('main', ['tx_dlf' => [ 'id' => 999999 ] ]);

        $response = $controller->processRequest($request);

        $this->assertSame(404, $response->getStatusCode());
        $response->getBody()->rewind();
        $this->assertSame('<html>notFound:1</html>', $response->getBody()->getContents());
    }
}
