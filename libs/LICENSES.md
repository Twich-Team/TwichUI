# Bundled libraries

| Library | License | Notes |
|---|---|---|
| LibStub | Public domain | |
| CallbackHandler-1.0 | BSD (Ace3) | |
| AceComm-3.0 | BSD (Ace3) | |
| ChatThrottleLib | Public domain | |
| LibSharedMedia-3.0 | LGPL v2.1 | unmodified |
| LibSerialize | MIT | **patched**: WoW's Lua raises an error on division by zero, so negative-zero detection and NaN creation were rewritten without dividing. Search for "TwichUI patch". |
| LibDeflate | zlib | |

LibSerialize is bundled (not pulled in by the packager) because of that patch.
If you update it, re-apply the patch or check that upstream fixed it.
