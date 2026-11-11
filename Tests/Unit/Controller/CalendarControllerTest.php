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
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;

/**
 * @covers \Kitodo\Dlf\Controller\CalendarController::formatCalendarTitle
 * @covers \Kitodo\Dlf\Controller\CalendarController::withCalendarVolume
 */
class CalendarControllerTest extends TestCase
{
    #[DataProvider('volumeProvider')]
    #[Test]
    public function withCalendarVolumeAppendsVolumeOnlyOnAmbiguousDays(string $title, string $volume, bool $ambiguous, string $expected): void
    {
        $subject = new CalendarController();

        $this->assertSame($expected, $subject->withCalendarVolume($title, $volume, $ambiguous));
    }

    public static function volumeProvider(): \Generator
    {
        yield 'ambiguous day with volume gets the number' => [
            '21.09.1939',
            'Nr. 221',
            true,
            '21.09.1939 Nr. 221',
        ];
        yield 'single issue day is untouched' => [
            '21.09.1939',
            'Nr. 221',
            false,
            '21.09.1939',
        ];
        yield 'ambiguous day without volume is untouched' => [
            '21.09.1939',
            '',
            true,
            '21.09.1939',
        ];
        yield 'title already containing the volume is untouched' => [
            '21.09.1939 Nr. 221',
            'Nr. 221',
            true,
            '21.09.1939 Nr. 221',
        ];
        yield 'non-date title gets the volume on ambiguous days' => [
            'Sonderausgabe',
            'Nr. 221',
            true,
            'Sonderausgabe Nr. 221',
        ];
        yield 'empty title is untouched' => [
            '',
            'Nr. 221',
            true,
            '',
        ];
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

    #[DataProvider('fullDatesProvider')]
    #[Test]
    public function formatCalendarTitleRendersFullDateWithFourDigitYear(string $title): void
    {
        $subject = new CalendarController();

        $actual = $subject->formatCalendarTitle($title);

        // Both German (19.04.1888) and ISO (1888-04-19) forms must expose the
        // full day.month.year with a four-digit year (never "19.04.88" or "1888").
        $this->assertMatchesRegularExpression('/19[.\-\/]04[.\-\/]1888|1888[.\-\/]04[.\-\/]19/', $actual);
    }

    public static function fullDatesProvider(): \Generator
    {
        yield 'dot date' => ['19.04.1888'];
        yield 'iso date' => ['1888-04-19'];
    }

    #[DataProvider('appendedTextProvider')]
    #[Test]
    public function formatCalendarTitleKeepsTextAfterDate(string $title): void
    {
        $subject = new CalendarController();

        $actual = $subject->formatCalendarTitle($title);

        // The date is localized and the appended text is preserved.
        $this->assertStringContainsString('Nr. 220', $actual);
        $this->assertMatchesRegularExpression('/21[.\-\/]09[.\-\/]1939|1939[.\-\/]09[.\-\/]21/', $actual);
    }

    public static function appendedTextProvider(): \Generator
    {
        yield 'dot date with issue number' => ['21.09.1939 Nr. 220'];
        yield 'iso date with issue number' => ['1939-09-21 Nr. 220'];
    }
}
