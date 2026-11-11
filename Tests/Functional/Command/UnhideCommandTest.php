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

namespace Kitodo\Dlf\Tests\Functional\Command;

use Kitodo\Dlf\Common\AbstractDocument;
use Kitodo\Dlf\Common\Helper;
use Kitodo\Dlf\Command\HideCommand;
use Kitodo\Dlf\Command\UnhideCommand;
use Kitodo\Dlf\Common\Indexer;
use Kitodo\Dlf\Common\Solr\Solr;
use Kitodo\Dlf\Domain\Model\SolrCore;
use Kitodo\Dlf\Domain\Repository\DocumentRepository;
use Kitodo\Dlf\Domain\Repository\SolrCoreRepository;
use Kitodo\Dlf\Tests\Functional\FunctionalTestCase;
use PHPUnit\Framework\Attributes\Test;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Tester\CommandTester;
use TYPO3\CMS\Core\Database\ConnectionPool;
use TYPO3\CMS\Core\Utility\GeneralUtility;

class UnhideCommandTest extends FunctionalTestCase
{
    protected DocumentRepository $documentRepository;

    protected SolrCoreRepository $solrCoreRepository;

    protected function setUp(): void
    {
        parent::setUp();

        $this->documentRepository = $this->initializeRepository(DocumentRepository::class, 20000);
        $this->solrCoreRepository = $this->initializeRepository(SolrCoreRepository::class, 20000);

        $this->importCSVDataSet(__DIR__ . '/../../Fixtures/Common/documents_1.csv');
        $this->importCSVDataSet(__DIR__ . '/../../Fixtures/Common/libraries.csv');
        $this->importCSVDataSet(__DIR__ . '/../../Fixtures/Common/metadata.csv');
    }

    #[Test]
    public function unhidesDocumentAndReindexesItInSolr(): void
    {
        $core = $this->createSolrCore();
        $this->indexDocument(1001, $core);

        // Hide the document first so it is visible again after unhide.
        $hideCommand = GeneralUtility::makeInstance(HideCommand::class);
        $hideTester = new CommandTester($hideCommand);
        $hideTester->execute([
            '--doc' => '1001',
            '--pid' => '20000',
            '--solr' => $core->model->getIndexName(),
        ]);
        self::assertSame(Command::SUCCESS, $hideTester->getStatusCode());
        self::assertDocumentHidden(1001, true);
        self::assertSame(0, $this->countSolrRows($core->solr, 1001));

        $unhideCommand = GeneralUtility::makeInstance(UnhideCommand::class);
        $unhideTester = new CommandTester($unhideCommand);
        $unhideTester->execute([
            '--doc' => '1001',
            '--pid' => '20000',
            '--solr' => $core->model->getIndexName(),
        ]);

        self::assertSame(Command::SUCCESS, $unhideTester->getStatusCode());
        self::assertDocumentHidden(1001, false);
        self::assertGreaterThanOrEqual(1, $this->countSolrRows($core->solr, 1001));
    }

    #[Test]
    public function reportsFailureForMissingDocument(): void
    {
        $core = $this->createSolrCore();

        $command = GeneralUtility::makeInstance(UnhideCommand::class);
        $tester = new CommandTester($command);
        $tester->execute([
            '--doc' => '424242',
            '--pid' => '20000',
            '--solr' => $core->model->getIndexName(),
        ]);

        self::assertSame(Command::FAILURE, $tester->getStatusCode());
    }

    protected function createSolrCore(): object
    {
        Helper::resetIndexNameCache();
        $coreName = Solr::createCore();
        $solr = Solr::getInstance($coreName);

        $model = GeneralUtility::makeInstance(SolrCore::class);
        $model->setLabel('Unhide command test core');
        $model->setIndexName($coreName);
        $this->solrCoreRepository->add($model);
        $this->persistenceManager->persistAll();

        return (object) compact('solr', 'model');
    }

    protected function indexDocument(int $uid, object $core): void
    {
        $document = $this->documentRepository->findByUid($uid);
        $document->setSolrcore($core->model->getUid());
        $this->persistenceManager->persistAll();

        $doc = AbstractDocument::getInstance($document->getLocation(), ['useExternalApisForMetadata' => 0, 'storagePid' => $document->getPid()]);
        $document->setCurrentDocument($doc);

        self::assertTrue(Indexer::add($document, $this->documentRepository));
    }

    protected function assertDocumentHidden(int $uid, bool $hidden): void
    {
        $queryBuilder = GeneralUtility::makeInstance(ConnectionPool::class)
            ->getQueryBuilderForTable('tx_dlf_documents');

        $result = $queryBuilder
            ->select('hidden')
            ->from('tx_dlf_documents')
            ->where($queryBuilder->expr()->eq('uid', $uid))
            ->executeQuery();

        self::assertSame($hidden ? 1 : 0, (int) $result->fetchOne());
    }

    protected function countSolrRows(Solr $solr, int $uid): int
    {
        $select = $solr->service->createSelect();
        $select->setQuery('uid:' . $uid);
        $result = $solr->service->select($select);

        return (int) $result->getNumFound();
    }
}
