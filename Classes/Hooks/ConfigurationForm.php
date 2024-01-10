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

namespace Kitodo\Dlf\Hooks;

use Kitodo\Dlf\Common\Helper;
use Kitodo\Dlf\Common\Solr\Solr;
use TYPO3\CMS\Core\Messaging\FlashMessage;

/**
 * Hooks and helper for \TYPO3\CMS\Core\TypoScript\ConfigurationForm
 *
 * @package TYPO3
 * @subpackage dlf
 *
 * @access public
 */
class ConfigurationForm
{

    /**
     * Check if a connection to a Solr server could be established with the given credentials.
     *
     * @access public
     *
     * @return string Message informing the user of success or failure
     */
    public function checkSolrConnection(): string
    {
        $solr = Solr::getInstance();
        if ($solr->ready) {
            Helper::addMessage(
                Helper::getLanguageService()->getLL('solr.status'),
                Helper::getLanguageService()->getLL('solr.connected'),
                FlashMessage::OK
            );
        } else {
            Helper::addMessage(
                Helper::getLanguageService()->getLL('solr.error'),
                Helper::getLanguageService()->getLL('solr.notConnected'),
                FlashMessage::WARNING
            );
        }
        return Helper::renderFlashMessages();
    }

    /**
     * Check if a connection to a OCRD server could be established with the given credentials.
     *
     * @access public
     *
     * @return string Message informing the user of success or failure
     */
    public function checkOCRDConnection()
    {
        $conf = \TYPO3\CMS\Core\Utility\GeneralUtility::makeInstance(\TYPO3\CMS\Core\Configuration\ExtensionConfiguration::class)->get('dlf');

        exec(" ssh -q -o BatchMode=yes -o ConnectTimeout=2 ".$conf['ocrdHost']." 'exit 0' ", $output, $retval);

        if ($retval == 0) {
            Helper::addMessage(
                Helper::getLanguageService()->getLL('ocrd.status'),
                Helper::getLanguageService()->getLL('ocrd.connected'),
                \TYPO3\CMS\Core\Messaging\FlashMessage::OK
            );
        } else {
            Helper::addMessage(
                Helper::getLanguageService()->getLL('ocrd.error'),
                Helper::getLanguageService()->getLL('ocrd.notConnected'),
                \TYPO3\CMS\Core\Messaging\FlashMessage::WARNING
            );
        }
        return Helper::renderFlashMessages();
    }

    /**
     * Loads all active OCR Engines from given json-file
     *
     * @access public
     *
     * @return string Message informing the user of success or failure
     */
    public function printActiveOCREngines()
    {
        $conf = \TYPO3\CMS\Core\Utility\GeneralUtility::makeInstance(\TYPO3\CMS\Core\Configuration\ExtensionConfiguration::class)->get('dlf');
        $ocrEnginesJson = json_decode(file_get_contents("../".$conf['ocrEngines']."/".$conf['ocrEnginesConfig']), true); # working dir is '/var/www/typo3/public/typo3'
        $ocrEnginesDir = "../".$conf['ocrEngines'];
        $files = scandir($ocrEnginesDir);
        $ocrEngines = array(); // All ocrEngines in the directory
        $activeOcrEngines = array(); // All active OCR engines

        // Get all .sh files in the ocrEngines directory
        foreach ($files as $file) {
            if (is_file($ocrEnginesDir . '/' . $file) && pathinfo($file, PATHINFO_EXTENSION) == 'sh') {
                if ($file != 'OCRmain.sh' && $file != 'UpdateMets.sh') {
                    $ocrEngines[] = explode(".", $file)[0];
                }
            }
        }

        // Get all active OCR engines:
        foreach ($ocrEnginesJson['ocrEngines'] as $engine) {
            $activeOcrEngines[] = $engine['data'];
            $engine = $engine['data'];
        }

        $ocrEnginesStr = '';
        foreach ($ocrEngines as $engine) {
            $nbSpace="&nbsp;&nbsp;";
            if (in_array($engine, $activeOcrEngines)) {
                $ocrEnginesStr .= $nbSpace . ' • <b>' . $engine . '</b><font color="darkgreen"> [active]</font><br>';
            } else {
                $ocrEnginesStr .= $nbSpace . ' • ' . $engine .'<font color="orange"> [not active]</font><br>';
            }
        }

        // Build feedback:
        if ($ocrEnginesJson !== null) {
            Helper::addMessage(
                $ocrEnginesStr,
                Helper::getLanguageService()->getLL('ocrEngines.loaded'), #engines loaded
                \TYPO3\CMS\Core\Messaging\FlashMessage::OK
            );
        } else {
            Helper::addMessage(
                "-",
                Helper::getLanguageService()->getLL('ocr.notLoaded'), #engine file not loaded
                \TYPO3\CMS\Core\Messaging\FlashMessage::WARNING
            );
        }
        return Helper::renderFlashMessages();
    }

    /**
     * This is the constructor.
     *
     * @access public
     *
     * @return void
     */
    public function __construct()
    {
        // Load backend localization file.
        Helper::getLanguageService()->includeLLFile('EXT:dlf/Resources/Private/Language/locallang_be.xlf');
    }

}
