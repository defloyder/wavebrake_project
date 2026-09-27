<?php

namespace Tests\Unit;

use App\Support\ByteFormatter;
use PHPUnit\Framework\TestCase;

class ByteFormatterTest extends TestCase
{
    public function test_binary_units(): void
    {
        $this->assertSame('0 B', ByteFormatter::format(0));
        $this->assertSame('512 B', ByteFormatter::format(512));
        $this->assertSame('1.5 MB', ByteFormatter::format(1572864));
        $this->assertSame('100 GB', ByteFormatter::format(107374182400));
        $this->assertSame('1 TB', ByteFormatter::format(1099511627776));
        $this->assertSame('∞', ByteFormatter::format(null));
    }
}
