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

namespace Kitodo\Dlf\Tests\Unit\Controller;

use Kitodo\Dlf\Controller\CalendarController;
use Kitodo\Dlf\Domain\Model\Document;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;

/**
 * @covers \Kitodo\Dlf\Controller\CalendarController::formatCalendarTitle
 * @covers \Kitodo\Dlf\Controller\CalendarController::withCalendarSuffix
 */
class CalendarControllerTest extends TestCase
{
    #[DataProvider('suffixedDatesProvider')]
    #[Test]
    public function formatCalendarTitleKeepsSuffixOfDateTitles(string $title, string $expectedSuffix): void
    {
        $subject = new CalendarController();

        $actual = $subject->formatCalendarTitle($title);

        $this->assertStringEndsWith(' ' . $expectedSuffix, $actual);
        $this->assertStringNotContainsString('_' . $expectedSuffix, $actual);
    }

    public static function suffixedDatesProvider(): \Generator
    {
        yield 'dot date with sond suffix' => ['21.09.1939_sond', 'Sonderblatt'];
        yield 'iso date with sond suffix' => ['1939-09-21_sond', 'Sonderblatt'];
        yield 'dot date with unknown suffix is kept verbatim' => ['21.09.1939-zusatz', 'zusatz'];
    }

    #[DataProvider('plainTitlesProvider')]
    #[Test]
    public function formatCalendarTitleReturnsNonDateTitlesUnchanged(string $title): void
    {
        $subject = new CalendarController();

        $this->assertSame($title, $subject->formatCalendarTitle($title));
    }

    public static function plainTitlesProvider(): \Generator
    {
        yield 'issue number' => ['Nr. 94'];
        yield 'empty string' => [''];
        yield 'free text' => ['Sonderausgabe'];
    }

    #[DataProvider('suffixProvider')]
    #[Test]
    public function withCalendarSuffixMarksSonderIssues(string $recordId, string $title, string $expected): void
    {
        $subject = new CalendarController();
        $document = new Document();
        $document->setRecordId($recordId);

        $this->assertSame($expected, $subject->withCalendarSuffix($title, $document));
    }

    public static function suffixProvider(): \Generator
    {
        yield 'regular issue is untouched' => [
            'DeutReunP_856399094_19390921',
            '21.09.1939',
            '21.09.1939',
        ];
        yield 'sonder issue gets a marker' => [
            'DeutReunP_856399094_19390921_sond',
            '21.09.1939',
            '21.09.1939_sond',
        ];
        yield 'title with its own suffix is untouched' => [
            'DeutReunP_856399094_19390921_sond',
            '21.09.1939_sond',
            '21.09.1939_sond',
        ];
        yield 'non-date title is untouched' => [
            '473889722_18810006_s',
            'Nr. 2',
            'Nr. 2',
        ];
    }
}
