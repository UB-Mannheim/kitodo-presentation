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

namespace Kitodo\Dlf\Tests\Unit\ExpressionLanguage;

use Kitodo\Dlf\Common\DocumentCacheManager;
use Kitodo\Dlf\Domain\Model\Document;
use Kitodo\Dlf\Domain\Repository\DocumentRepository;
use Kitodo\Dlf\ExpressionLanguage\DocumentTypeFunctionProvider;
use PHPUnit\Framework\Attributes\Test;
use Psr\Log\LoggerInterface;
use TYPO3\CMS\Core\Utility\GeneralUtility;
use TYPO3\TestingFramework\Core\Unit\UnitTestCase;

class DocumentTypeFunctionProviderTest extends UnitTestCase
{
    protected bool $resetSingletonInstances = true;

    protected function tearDown(): void
    {
        GeneralUtility::purgeInstances();
        parent::tearDown();
    }

    /**
     * A document record exists, but the METS/IIIF fetch failed (e.g. network
     * timeout). The error message must tell that the record was FOUND but
     * could not be loaded from its location, not that the UID is invalid.
     */
    #[Test]
    public function loadDocumentLogsFetchFailureWhenRecordExistsButFetchFails(): void
    {
        $logger = $this->createMock(LoggerInterface::class);
        $provider = $this->createProvider($logger);
        $documentMock = $this->createMock(Document::class);
        $documentMock->method('getLocation')->willReturn('https://example.com/restricted/x/x.xml');
        $this->injectDocumentRepository($provider, $this->createDocumentRepositoryMock($documentMock));
        // The document cache reports that loading this location failed
        // before, so AbstractDocument::getInstance() returns null without
        // any network access.
        $this->stubDocumentCacheAsFailed('https://example.com/restricted/x/x.xml');
        $logger->expects(self::once())
            ->method('error')
            ->with(self::stringContains('found, but could not be loaded from "https://example.com/restricted/x/x.xml"'));

        $provider->loadDocumentForTest(['id' => 42], 3);

        // The record itself was found, only loading its location failed.
        self::assertSame($documentMock, $provider->getDocumentForTest());
    }

    /**
     * The document record does not exist (e.g. stale UID from an old Solr
     * index). The error message must tell that the record was NOT FOUND,
     * not that loading from some location failed.
     */
    #[Test]
    public function loadDocumentLogsNotFoundWhenRecordMissing(): void
    {
        $logger = $this->createMock(LoggerInterface::class);
        $provider = $this->createProvider($logger);
        $this->injectDocumentRepository($provider, $this->createDocumentRepositoryMock());
        $logger->expects(self::once())
            ->method('error')
            ->with(self::stringContains('Document UID "42" not found on storage page "3"'));

        $provider->loadDocumentForTest(['id' => 42], 3);

        self::assertNull($provider->getDocumentForTest());
    }

    /**
     * No document id and no record id in the request data.
     */
    #[Test]
    public function loadDocumentLogsMissingIdWhenRequestDataEmpty(): void
    {
        $logger = $this->createMock(LoggerInterface::class);
        $provider = $this->createProvider($logger);
        $logger->expects(self::once())
            ->method('error')
            ->with(self::stringContains('No document ID or record ID given for document loading'));

        $provider->loadDocumentForTest([], 3);

        self::assertNull($provider->getDocumentForTest());
    }

    private function createProvider(LoggerInterface $logger): DocumentTypeFunctionProvider
    {
        $provider = new class () extends DocumentTypeFunctionProvider {
            // Skip the extbase/TypoScript bootstrap (needs a full
            // frontend request); the repository is injected directly.
            protected function initializeRepositories(int $storagePid): void
            {
            }

            public function loadDocumentForTest(array $requestData, int $storagePid): void
            {
                $this->loadDocument($requestData, $storagePid);
            }

            public function getDocumentForTest(): ?Document
            {
                return $this->document ?? null;
            }
        };
        $provider->setLogger($logger);
        return $provider;
    }

    private function createDocumentRepositoryMock(?Document $document = null): DocumentRepository
    {
        $repositoryMock = $this->createMock(DocumentRepository::class);
        $repositoryMock->method('findByUid')->willReturn($document);
        return $repositoryMock;
    }

    private function stubDocumentCacheAsFailed(string $location): void
    {
        $cacheManager = $this->createMock(DocumentCacheManager::class);
        $cacheManager->method('get')->willReturnCallback(
            static fn (string $stubLocation) => $stubLocation === $location ? DocumentCacheManager::LOAD_FAILED : false
        );
        GeneralUtility::setSingletonInstance(DocumentCacheManager::class, $cacheManager);
    }

    private function injectDocumentRepository(DocumentTypeFunctionProvider $provider, DocumentRepository $repository): void
    {
        $property = new \ReflectionProperty(DocumentTypeFunctionProvider::class, 'documentRepository');
        $property->setValue($provider, $repository);
    }
}
