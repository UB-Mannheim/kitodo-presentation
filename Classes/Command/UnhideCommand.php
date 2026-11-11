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

namespace Kitodo\Dlf\Command;

use Kitodo\Dlf\Common\AbstractDocument;
use Kitodo\Dlf\Common\DocumentCacheManager;
use Kitodo\Dlf\Common\Indexer;
use Kitodo\Dlf\Domain\Model\Document;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Input\InputOption;
use Symfony\Component\Console\Output\OutputInterface;
use Symfony\Component\Console\Style\SymfonyStyle;
use TYPO3\CMS\Core\Utility\GeneralUtility;
use TYPO3\CMS\Core\Utility\MathUtility;

/**
 * CLI Command for unhiding single documents in database and reindexing them in Solr.
 *
 * @package TYPO3
 * @subpackage dlf
 *
 * @access public
 */
class UnhideCommand extends BaseCommand
{
    /**
     * Configure the command by defining the name, options and arguments
     *
     * @access public
     *
     * @return void
     */
    public function configure(): void
    {
        $this
            ->setDescription('Unhide document(s) in the database and reindex them in Solr.')
            ->setHelp('')
            ->addOption(
                'doc',
                'd',
                InputOption::VALUE_REQUIRED,
                'UID or URL of the document. Comma-separated lists are allowed.'
            )
            ->addOption(
                'pid',
                'p',
                InputOption::VALUE_REQUIRED,
                'UID of the page the document should be added to.'
            )
            ->addOption(
                'solr',
                's',
                InputOption::VALUE_REQUIRED,
                '[UID|index_name] of the Solr core the document should be indexed in.'
            )
            ->addOption(
                'with-children',
                'wc',
                InputOption::VALUE_NONE,
                'If this option is set, all direct child documents are unhidden as well.'
            )
            ->addOption(
                'softCommit',
                null,
                InputOption::VALUE_NONE,
                'If this option is set, documents are just added to the index by a soft commit.'
            )
            ->addOption(
                'dry-run',
                null,
                InputOption::VALUE_NONE,
                'If this option is set, nothing is written to the database or the index. Only the affected documents are shown.'
            );
    }

    /**
     * Executes the command to unhide the given documents in database and reindex them in Solr.
     *
     * @access protected
     *
     * @param InputInterface $input The input parameters
     * @param OutputInterface $output The Symfony interface for outputs on console
     *
     * @return int
     */
    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $io = new SymfonyStyle($input, $output);
        $io->title($this->getDescription());

        $this->initializeRepositories((int) $input->getOption('pid'));

        if ($this->storagePid == 0) {
            return $this->handlePidError($io);
        }

        if (
            !empty($input->getOption('solr'))
            && !is_array($input->getOption('solr'))
        ) {
            $allSolrCores = $this->getSolrCores($this->storagePid);
            $solrCoreUid = $this->getSolrCoreUid($allSolrCores, $input->getOption('solr'));

            // Abort if solrCoreUid is empty or not in the array of allowed solr cores.
            if (empty($solrCoreUid) || !in_array($solrCoreUid, $allSolrCores)) {
                return $this->handleSolrError($allSolrCores, $input->getOption('solr'), $io);
            }
        } else {
            return $this->handleSolrMissingError($io);
        }

        $docOption = $input->getOption('doc');
        if (
            empty($docOption)
            || is_array($docOption)
        ) {
            $io->error('Required parameter --doc|-d is missing or invalid.');
            return Command::FAILURE;
        }

        $dryRun = $input->getOption('dry-run') != false;
        $withChildren = $input->getOption('with-children') != false;
        $softCommit = $input->getOption('softCommit');

        $lError = false;
        $unhiddenCount = 0;
        $childCount = 0;

        foreach (GeneralUtility::trimExplode(',', (string) $docOption, true) as $doc) {
            $row = $this->resolveDocument($doc);
            if ($row === null) {
                $io->error(sprintf('Document "%s" not found in the database (deleted or never imported).', $doc));
                $io->warning('If it should exist, index it first with kitodo:index.');
                $lError = true;
                continue;
            }

            $uids = [(int) $row['uid']];
            if ($withChildren) {
                foreach ($this->findChildUids((int) $row['uid']) as $childUid) {
                    $uids[] = $childUid;
                }
            }
            $uids = array_values(array_unique($uids));

            foreach ($uids as $uid) {
                if ($dryRun) {
                    $io->writeln(sprintf('DRY RUN: Would unhide document with UID "%d" and reindex it in Solr core %d.', $uid, $solrCoreUid));
                    continue;
                }

                if ($io->isVerbose()) {
                    $io->writeln(date('Y-m-d H:i:s') . ' Unhiding document with UID "' . $uid . '" and reindexing it in Solr core ' . $solrCoreUid . '.');
                }

                $affected = $this->setDocumentHidden($uid, false);
                if ($affected === 0) {
                    $io->warning(sprintf('Document with UID "%d" not found in the database. Skip to next document.', $uid));
                    $lError = true;
                    continue;
                }

                if (!$this->reindexDocument($uid, $softCommit)) {
                    $io->error(sprintf('Document with UID "%d" was unhidden but could not be reindexed in the Solr core "%d". Check log file for more details!', $uid, $solrCoreUid));
                    $lError = true;
                    continue;
                }

                if ($uid === (int) $row['uid']) {
                    $unhiddenCount++;
                } else {
                    $childCount++;
                }
            }
        }

        if ($lError) {
            $io->error('At least one error!');
            return Command::FAILURE;
        }

        if ($dryRun) {
            $io->success('End reached');
            return Command::SUCCESS;
        }

        $io->success(sprintf('Unhidden %d document(s) (incl. %d children) and reindexed them in Solr core %d.', $unhiddenCount, $childCount, $solrCoreUid));
        return Command::SUCCESS;
    }

    /**
     * Reindex the given document in Solr.
     *
     * The document entity is looked up with hidden records included, because
     * the unhidden flag was just written directly to the database.
     *
     * @access private
     *
     * @param int $uid The document uid
     * @param bool $softCommit If true, the document is just added to the index by a soft commit
     *
     * @return bool true on success or false on failure
     */
    private function reindexDocument(int $uid, bool $softCommit): bool
    {
        $this->documentRepository->showHidden();

        /** @var Document|null $document */
        $document = $this->documentRepository->findByUid($uid);
        if ($document === null) {
            return false;
        }

        $abstractDocument = AbstractDocument::getInstance($document->getLocation(), ['storagePid' => $document->getPid()], true);
        if ($abstractDocument === null) {
            return false;
        }

        $document->setCurrentDocument($abstractDocument);
        $isIndexed = Indexer::add($document, $this->documentRepository, $softCommit);

        // Clear document cache to prevent stale data on the next load.
        GeneralUtility::makeInstance(DocumentCacheManager::class)->remove($document->getLocation());

        return $isIndexed;
    }

    /**
     * Resolve the given UID or URL to a non-deleted database record.
     *
     * @access private
     *
     * @param string $doc The document UID or URL
     *
     * @return array<string, mixed>|null The record fields or null
     */
    private function resolveDocument(string $doc): ?array
    {
        if (MathUtility::canBeInterpretedAsInteger($doc)) {
            return $this->findDocumentRow((int) $doc);
        }

        if (!GeneralUtility::isValidUrl($doc)) {
            return null;
        }

        $abstractDocument = AbstractDocument::getInstance($doc, ['storagePid' => $this->storagePid], true);
        if ($abstractDocument !== null && !empty($abstractDocument->recordId)) {
            return $this->findDocumentRowByRecordId($abstractDocument->recordId);
        }

        return $this->findDocumentRowByLocation($doc);
    }
}
