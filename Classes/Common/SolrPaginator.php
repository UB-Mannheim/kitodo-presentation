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

namespace Kitodo\Dlf\Common;

use Kitodo\Dlf\Common\Solr\SolrSearch;
use TYPO3\CMS\Core\Pagination\AbstractPaginator;

class SolrPaginator extends AbstractPaginator
{
    /**
     * @var SolrSearch
     */
    private SolrSearch $solrSearch;

    /**
     * @var array
     */
    private array $paginatedItems = [];

    public function __construct(
        SolrSearch $solrSearch,
        int $currentPageNumber = 1,
        int $itemsPerPage = 25
    ) {
	$ipAddress = $_SERVER['REMOTE_ADDR'] ?? '';
	if ($ipAddress == '134.155.60.28') {
		\TYPO3\CMS\Extbase\Utility\DebuggerUtility::var_dump('$solrSearch');
		\TYPO3\CMS\Extbase\Utility\DebuggerUtility::var_dump($solrSearch);
	};
    
        $this->solrSearch = $solrSearch;
	if ($ipAddress == '134.155.60.28') {
		\TYPO3\CMS\Extbase\Utility\DebuggerUtility::var_dump('$this 1');
		\TYPO3\CMS\Extbase\Utility\DebuggerUtility::var_dump($this);
	};
        $this->setCurrentPageNumber($currentPageNumber);
	if ($ipAddress == '134.155.60.28') {
		\TYPO3\CMS\Extbase\Utility\DebuggerUtility::var_dump('$this 2');
		\TYPO3\CMS\Extbase\Utility\DebuggerUtility::var_dump($this);
	};
        $this->setItemsPerPage($itemsPerPage);
	if ($ipAddress == '134.155.60.28') {
		\TYPO3\CMS\Extbase\Utility\DebuggerUtility::var_dump('$this 3');
		\TYPO3\CMS\Extbase\Utility\DebuggerUtility::var_dump($this);
		\TYPO3\CMS\Extbase\Utility\DebuggerUtility::var_dump('$this vor 4');		
	};

        $this->updateInternalState();
	// Hier geht etwas schief, kein Ergebnis
	if ($ipAddress == '134.155.60.28') {
		\TYPO3\CMS\Extbase\Utility\DebuggerUtility::var_dump('$this 4');
		\TYPO3\CMS\Extbase\Utility\DebuggerUtility::var_dump($this);
	};
	
	
    }

    protected function updatePaginatedItems(int $itemsPerPage, int $offset): void
    {
	$ipAddress = $_SERVER['REMOTE_ADDR'] ?? '';
	if ($ipAddress == '134.155.60.28') {
		//$offset = 1;
		\TYPO3\CMS\Extbase\Utility\DebuggerUtility::var_dump('$offset');
		\TYPO3\CMS\Extbase\Utility\DebuggerUtility::var_dump($offset);
		\TYPO3\CMS\Extbase\Utility\DebuggerUtility::var_dump('$itemsPerPage');
		\TYPO3\CMS\Extbase\Utility\DebuggerUtility::var_dump($itemsPerPage);
	};
        $this->solrSearch->submit($offset, $itemsPerPage);
        $this->paginatedItems = $this->solrSearch->toArray();
    }

    protected function getTotalAmountOfItems(): int
    {
	$ipAddress = $_SERVER['REMOTE_ADDR'] ?? '';
	if ($ipAddress == '134.155.60.28') {
		\TYPO3\CMS\Extbase\Utility\DebuggerUtility::var_dump('$this->solrSearch->count()');
		\TYPO3\CMS\Extbase\Utility\DebuggerUtility::var_dump($this->solrSearch->count());
	};
        return $this->solrSearch->count();
    }

    protected function getAmountOfItemsOnCurrentPage(): int
    {
	$ipAddress = $_SERVER['REMOTE_ADDR'] ?? '';
	if ($ipAddress == '134.155.60.28') {
		\TYPO3\CMS\Extbase\Utility\DebuggerUtility::var_dump('count($this->paginatedItems)');
		\TYPO3\CMS\Extbase\Utility\DebuggerUtility::var_dump(count($this->paginatedItems));
	};
        return count($this->paginatedItems);
    }

    public function getPaginatedItems(): iterable
    {
	$ipAddress = $_SERVER['REMOTE_ADDR'] ?? '';
	if ($ipAddress == '134.155.60.28') {
		\TYPO3\CMS\Extbase\Utility\DebuggerUtility::var_dump('$this->paginatedItems');
		\TYPO3\CMS\Extbase\Utility\DebuggerUtility::var_dump($this->paginatedItems);
		\TYPO3\CMS\Extbase\Utility\DebuggerUtility::var_dump('$this von getPaginatedItems');
		\TYPO3\CMS\Extbase\Utility\DebuggerUtility::var_dump($this);
	};
        return $this->paginatedItems;
    }
}
