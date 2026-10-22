# Walidacja pierwszych IPA — 21.10.2026

Kod aplikacji: commit `66979d8d48449b4e0ae0ee1aef23026a59d5ad8e`. [Kompilacja i raporty](https://github.com/Palamabron/iphone-personal-apps/actions/runs/39633098802) zakończone sukcesem dla obu aplikacji. Kolejne zmiany dokumentacji nie modyfikują kodu tego wydania.

## Wykonane

- Standardowe publiczne runnery `macos-15`, Xcode 16.4, iPhoneOS SDK 18.5. Docelowy iOS 18.0+, ARM64, konfiguracja Release.
- 7 testów logiki Focus Tube i 20 testów logiki/kolektora Radaru na runnerach macOS.
- Poprawne zbudowanie obu aplikacji oraz rozszerzenia Safari. Brak danych Apple Account i profili podpisujących w kompilacji.
- Kontrola ZIP/Info.plist/Mach-O: pakiety dla iPhoneOS i ARM64, zgodne identyfikatory oraz wersje, ikony, kod i zasoby aplikacji. Focus zawiera rozszerzenie Safari, manifest ograniczony do YouTube, polski ekran konfiguracji i link zmiany konta. Radar zawiera samowystarczalny HTML z mostem natywnym.
- Kontrolę paczek powtórzono po pobraniu z GitHub Actions na Windowsa. Sumy SHA-256 są zgodne z raportami CI.
- Wcześniejsza próba interfejsu Radaru w Chromium z zastąpionym mostem: zapis i ponowne otwarcie, eksport ICS/JSON, import publicznego źródła, odrzucenie obcych adresów, zachowanie zapisów po awarii źródeł. To nie jest test Swift ani mobilnego Safari.

| Plik | Bajty | SHA-256 |
|---|---:|---|
| FocusTube-unsigned.ipa | 103739 | `69ecf062f76e353e36e5a7654e0b0822d161e5961c61eea3fb67b0461eb9af9b` |
| TechRadar-unsigned.ipa | 108357 | `e178e41bcb4814f417effedda17060f5c3bc0e3a779f7ffe2de0f96c3bad4f68` |

## Niewykonane

Nie uruchomiono symulatora ani fizycznego iPhone'a. Do sprawdzenia: podpisanie SideStore i Personal Team (w tym rozszerzenie), uruchomienie i widoczność w Safari, rzeczywisty zapis/odtworzenie, udostępnianie i import plików, dostęp do źródeł z sieci telefonu, odnowienie bez utraty danych. Działanie konta YouTube/Premium, audio w tle i PiP nie zostało potwierdzone.

## Ostrzeżenia narzędzi

Generator rozszerzenia z Xcode 16.4 zgłasza klucz `content_scripts.world`. Pozostawiono `MAIN` i minimalny iOS 18. [Dane zgodności MDN](https://github.com/mdn/browser-compat-data/blob/main/webextensions/manifest/content_scripts.json) wskazują obsługę tego klucza od Safari 18. Samo zestawienie tych informacji nie jest testem Safari na telefonie. Runtime ma również obserwację DOM i okresowe sprawdzanie adresu; nie opiera całej nawigacji wyłącznie na podmianie metod historii.

Pozostały komunikaty pomijania metadanych AppIntents (aplikacje nie implementują App Intents) oraz komunikaty GitHub Actions o środowisku Node.js użytym przez akcje. Nie ma ostrzeżeń o brakujących ikonach ani błędów kompilacji.


## Focus Tube Native 0.2.0 — 22.10.2026

Kod aplikacji: `fda4586`. [Kompilacja 39696970191](https://github.com/Palamabron/iphone-personal-apps/actions/runs/39696970191) przeszła. To osobna aplikacja SwiftUI/WKWebView, a nie kontener rozszerzenia z wcześniejszego wydania.

- Testy JavaScript filtra: 7/7. Kontrola natywnej polityki URL w Swift: przeszła (wyszukiwanie, poprawne filmy, blokada Shorts, zakodowane adresy i podszywające się hosty). Dodatkowo istniejący filtr przeszedł 39 syntetycznych prób Chromium na Windowsie; nie są to próby WebKit.
- Xcode skompilował urządzeniową wersję Release iPhoneOS/ARM64, iOS 18+. Kontrola ZIP, Info.plist, ikony i wbudowanego filtra przeszła w CI oraz ponownie po pobraniu na Windowsa. Bundle `dev.palamabron.focustube.native`, wersja 0.2.0, bez rozszerzeń i bez podpisu.
- Osobna kompilacja symulatora, instalacja, uruchomienie i zrzut ekranu przeszły. Ręczna inspekcja zrzutu potwierdziła poprawny polski ekran startowy i czytelny układ bez ucięć. Nie wykonywano w symulatorze wyszukiwania, odtwarzania, logowania ani testu zakładek.
- Paczka: `FocusTubeNative-unsigned.ipa`, 119891 bajtów, SHA-256 `628794525ab0561b4365af4cb54f33042c8151a0679f1805b90b62cd2bacf890`.

Niewykonane: podpisanie i instalacja SideStore, wyszukiwanie i odtwarzanie w rzeczywistym mobilnym YouTube/WKWebView, trwałość sesji i zapisów po zamknięciu, konto Google/Premium, PiP, tło i odnowienie podpisu na fizycznym iPhonie. Użytkownik podał iPhone 16 Pro/iOS 27.0.1; symulator nie jest testem tego zestawu. Google może odmówić osadzonego logowania. Instrukcja i zakres: FOCUS-NATIVE.md.
