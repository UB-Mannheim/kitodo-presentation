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

class MemDebugger
{
    private $io;
    private int $last = 0;
    
    public function __construct($io){
        $this->io = $io;
        $this->last = memory_get_usage();
    }

    public function print(string $msg='')
    {
        $now = memory_get_usage();
        $delta = 100.*($now - $this->last)/$this->last;
        $this->last = $now;
        $outstr = 'Mem usage: ' . $now
                . ' (' . ($delta > 0 ? '<fg=red>+' : '<fg=green>')
                . number_format($delta, 4) . '%</>)';
        if (strlen($msg))
        {
            $outstr .= ', ' . $msg;
        }
        $this->io->writeln($outstr);
    }
}
