/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

// Empty stand-in for monaco's css / html / json / typescript language service
// registrations. See the monacoLanguageServiceStub plugin in vite.config.js
// for why they get dropped. Monaco's index.js re-exports each of these as a
// namespace (monaco.css, monaco.html, ...) so an empty module is enough - the
// namespaces just come out empty and nothing in COSMOS reads them.
export {}
