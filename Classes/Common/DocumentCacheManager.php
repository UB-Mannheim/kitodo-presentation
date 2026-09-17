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

use TYPO3\CMS\Core\Cache\CacheManager;
use TYPO3\CMS\Core\Cache\Frontend\FrontendInterface;
use TYPO3\CMS\Core\Configuration\ExtensionConfiguration;
use TYPO3\CMS\Core\SingletonInterface;
use TYPO3\CMS\Core\Utility\GeneralUtility;

/**
 * DocumentCacheManager class for the 'dlf' extension
 *
 * @package TYPO3
 * @subpackage dlf
 *
 * @access public
 */
class DocumentCacheManager implements SingletonInterface
{
    /**
     * @var FrontendInterface
     */
    protected $cache;

    /**
     * @var FrontendInterface
     */
    protected $failCache;

    /**
     * Constructor
     */
    public function __construct()
    {
        $cacheManager = GeneralUtility::makeInstance(CacheManager::class);
        $this->cache = $cacheManager->getCache('tx_dlf_doc');
        $this->failCache = $cacheManager->getCache('tx_dlf_doc_fail');
    }

    /**
     * Get document instance from cache or false if not found.
     *
     * @access public
     *
     * @param string $location
     *
     * @return AbstractDocument|false
     */
    public function get(string $location)
    {
        return $this->cache->get($this->getIdentifier($location));
    }

    /**
     * Get the cached "load failed" flag for a document location or false if not set.
     *
     * A failed load is recorded so that the same unloadable URL is not fetched
     * over the network again on every request.
     *
     * @access public
     *
     * @param string $location
     *
     * @return mixed
     */
    public function getFail(string $location)
    {
        return $this->failCache->get($this->getIdentifier($location));
    }

    /**
     * Remember that loading a document failed.
     *
     * The entry is cached for the configured fail-cache lifetime (a short
     * default is used so that a document that appears later is picked up
     * again) and can be removed via remove() like a regular entry.
     *
     * @access public
     *
     * @param string $location
     *
     * @return void
     */
    public function setFail(string $location): void
    {
        $this->failCache->set($this->getIdentifier($location), true, [], $this->getFailLifetime());
    }

    /**
     * Get the lifetime in seconds for cached "load failed" flags.
     *
     * @access private
     *
     * @return int
     */
    private function getFailLifetime(): int
    {
        $extConf = GeneralUtility::makeInstance(ExtensionConfiguration::class)->get('dlf', 'general');
        $lifetime = (int) ($extConf['failCacheLifetime'] ?? 0);
        return $lifetime > 0 ? $lifetime : 300;
    }

    /**
     * Remove all documents from cache.
     *
     * @access public
     *
     * @return void
     */
    public function flush(): void
    {
        $this->cache->flush();
        $this->failCache->flush();
    }

    /**
     * Remove single document from cache.
     *
     * @access public
     *
     * @param string $location
     *
     * @return void
     */
    public function remove(string $location): void
    {
        $this->cache->remove($this->getIdentifier($location));
        $this->failCache->remove($this->getIdentifier($location));
    }

    /**
     * Set cache for document instance.
     *
     * @access public
     *
     * @param string $location
     * @param AbstractDocument $currentDocument
     *
     * @return void
     */
    public function set(string $location, AbstractDocument $currentDocument): void
    {
        $this->cache->set($this->getIdentifier($location), $currentDocument);
    }

    /**
     * Get cache identifier for document location.
     *
     * @access private
     *
     * @param string $location
     *
     * @return string
     */
    private function getIdentifier(string $location): string
    {
        return hash('md5', $location);
    }
}
