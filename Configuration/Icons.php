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

use TYPO3\CMS\Core\Imaging\IconProvider\SvgIconProvider;

$iconPath = 'EXT:dlf/Resources/Public/Icons/';

return [
    'tx-dlf-basket' => [
        'provider' => SvgIconProvider::class,
        'source' => $iconPath . 'tx-dlf-basket.svg',
    ],
    'tx-dlf-calendar' => [
        'provider' => SvgIconProvider::class,
        'source' => $iconPath . 'tx-dlf-calendar.svg',
    ],
    'tx-dlf-collection' => [
        'provider' => SvgIconProvider::class,
        'source' => $iconPath . 'tx-dlf-collection.svg',
    ],
    'tx-dlf-embedded3dviewer' => [
        'provider' => SvgIconProvider::class,
        'source' => $iconPath . 'tx-dlf-embedded3dviewer.svg',
    ],
    'tx-dlf-feeds' => [
        'provider' => SvgIconProvider::class,
        'source' => $iconPath . 'tx-dlf-feeds.svg',
    ],
    'tx-dlf-listview' => [
        'provider' => SvgIconProvider::class,
        'source' => $iconPath . 'tx-dlf-listview.svg',
    ],
    'tx-dlf-mediaplayer' => [
        'provider' => SvgIconProvider::class,
        'source' => $iconPath . 'tx-dlf-mediaplayer.svg',
    ],
    'tx-dlf-metadata' => [
        'provider' => SvgIconProvider::class,
        'source' => $iconPath . 'tx-dlf-metadata.svg',
    ],
    'tx-dlf-navigation' => [
        'provider' => SvgIconProvider::class,
        'source' => $iconPath . 'tx-dlf-navigation.svg',
    ],
    'tx-dlf-oaipmh' => [
        'provider' => SvgIconProvider::class,
        'source' => $iconPath . 'tx-dlf-oaipmh.svg',
    ],
    'tx-dlf-pagegrid' => [
        'provider' => SvgIconProvider::class,
        'source' => $iconPath . 'tx-dlf-pagegrid.svg',
    ],
    'tx-dlf-pageview' => [
        'provider' => SvgIconProvider::class,
        'source' => $iconPath . 'tx-dlf-pageview.svg',
    ],
    'tx-dlf-search' => [
        'provider' => SvgIconProvider::class,
        'source' => $iconPath . 'tx-dlf-search.svg',
    ],
    'tx-dlf-statistics' => [
        'provider' => SvgIconProvider::class,
        'source' => $iconPath . 'tx-dlf-statistics.svg',
    ],
    'tx-dlf-tableofcontents' => [
        'provider' => SvgIconProvider::class,
        'source' => $iconPath . 'tx-dlf-tableofcontents.svg',
    ],
    'tx-dlf-toolbox' => [
        'provider' => SvgIconProvider::class,
        'source' => $iconPath . 'tx-dlf-toolbox.svg',
    ],
    'tx-dlf-validationform' => [
        'provider' => SvgIconProvider::class,
        'source' => $iconPath . 'tx-dlf-validationform.svg',
    ],
];
