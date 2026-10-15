package com.wavebreak.wavebreak

import org.junit.Assert.assertEquals
import org.junit.Test

/** Split tunneling: what establish() excludes from the tunnel. */
class SplitTunnelTest {
    private val own = "com.wavebreak.wavebreak"
    private val safetyNet = setOf("com.wildberries.ru", "ru.ozon.app.android")

    @Test
    fun withoutUserChoiceOnlyThisAppAndTheSafetyNet() {
        assertEquals(
            listOf(own, "com.wildberries.ru", "ru.ozon.app.android"),
            excludedPackages(own, safetyNet, emptyList()).toList(),
        )
    }

    @Test
    fun userAppsAreAddedAfterTheSafetyNet() {
        assertEquals(
            listOf(own, "com.wildberries.ru", "ru.ozon.app.android", "ru.sberbankmobile", "com.vkontakte.android"),
            excludedPackages(own, safetyNet, listOf("ru.sberbankmobile", "com.vkontakte.android")).toList(),
        )
    }

    @Test
    fun theSafetyNetStaysWhateverTheUserChose() {
        // The user can't put a marketplace back into the tunnel: it is
        // excluded either way, and listed once.
        val result = excludedPackages(own, safetyNet, listOf("com.wildberries.ru"))
        assertEquals(setOf(own, "com.wildberries.ru", "ru.ozon.app.android"), result)
        assertEquals(3, result.size)
    }

    @Test
    fun duplicatesBlanksAndThisAppAreListedOnce() {
        val result = excludedPackages(own, safetyNet, listOf(" ru.sberbankmobile ", "", "  ", own, "ru.sberbankmobile"))
        assertEquals(listOf(own, "com.wildberries.ru", "ru.ozon.app.android", "ru.sberbankmobile"), result.toList())
    }
}
