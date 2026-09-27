<?php

namespace Tests\Unit;

use App\Support\ByteFormatter;
use PHPUnit\Framework\TestCase;

class ByteFormatterTest extends TestCase
{
    public function test_binary_units_with_russian_labels(): void
    {
        $this->assertSame('0 Б', ByteFormatter::format(0));
        $this->assertSame('512 Б', ByteFormatter::format(512));
        $this->assertSame('1,5 МБ', ByteFormatter::format(1572864));
        $this->assertSame('100 ГБ', ByteFormatter::format(107374182400));
        $this->assertSame('1 ТБ', ByteFormatter::format(1099511627776));
        $this->assertSame('Безлимит', ByteFormatter::format(null));
    }

    public function test_fixed_gigabytes(): void
    {
        $this->assertSame('0 ГБ', ByteFormatter::gigabytes(0));
        $this->assertSame('0,5 ГБ', ByteFormatter::gigabytes(536870912));
        $this->assertSame('1 536 ГБ', ByteFormatter::gigabytes(1536 * ByteFormatter::GIB));
        $this->assertSame('Безлимит', ByteFormatter::gigabytes(null));
    }

    public function test_input_value(): void
    {
        $this->assertSame('100', ByteFormatter::gigabytesInput(107374182400));
        $this->assertSame('1.5', ByteFormatter::gigabytesInput(1610612736));
        $this->assertSame('', ByteFormatter::gigabytesInput(null));
    }
}
