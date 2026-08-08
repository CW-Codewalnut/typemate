package com.codewalnut.typemate

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Covers the decision behind the WhatsApp report: dictating produced
 * "Message, the actual message" because the placeholder was read as text
 * the user had typed.
 *
 * The service reads an AccessibilityNodeInfo, which cannot be constructed
 * in a JVM test, so the decision lives in a pure function and this pins it.
 * What still needs a real device is whether a given app populates hintText
 * at all — that is the one thing no test here can answer.
 */
class ExistingTextTest {
    @Test
    fun `a field flagged as showing its hint is empty`() {
        assertEquals("", existingTextFrom("Message", "Message", true))
    }

    @Test
    fun `a placeholder reported as text is treated as empty`() {
        // WhatsApp: renders "Message" as the node's own text and does not
        // set isShowingHintText.
        assertEquals("", existingTextFrom("Message", "Message", false))
    }

    @Test
    fun `a placeholder with stray whitespace is still a placeholder`() {
        assertEquals("", existingTextFrom(" Message ", "Message", false))
    }

    @Test
    fun `text the user typed is kept`() {
        assertEquals(
            "hello there",
            existingTextFrom("hello there", "Message", false),
        )
    }

    @Test
    fun `text that merely starts with the hint is kept`() {
        // "Search" against a hint of "Search or type URL" is real input.
        assertEquals(
            "Search",
            existingTextFrom("Search", "Search or type URL", false),
        )
    }

    @Test
    fun `a null hint leaves the text alone`() {
        assertEquals("hello", existingTextFrom("hello", null, false))
    }

    @Test
    fun `null text is empty`() {
        assertEquals("", existingTextFrom(null, "Message", false))
    }
}
