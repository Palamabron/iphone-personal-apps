# Radar jako własna aplikacja iPhone

Stan 21.10.2026: źródła hosta iOS i pipeline IPA są przygotowane. Nie wykonano kompilacji Xcode, testu symulatora ani instalacji na iPhonie. Dotychczasowa aplikacja webowa pozostaje dostępną, działającą wersją.

## Co jest w źródłach

`ios/RadarApp.swift` tworzy samodzielną aplikację iOS z lokalnie dołączonym interfejsem radaru. Wygląd, reguły dopasowania i parsery są te same co w aplikacji webowej; nie jest to ponownie napisany od zera interfejs SwiftUI. Swift zapewnia powłokę, trwały zapis w UserDefaults, systemowe udostępnianie ICS/kopii JSON i odczyt publicznych źródeł przez URLSession. Aplikacja nie wymaga logowania do prywatnego hostingu Sites ani serwera.

Źródła pobierane są z sieci telefonu. Obowiązują te same ograniczenia: błędy/limity Luma i Evenea są raportowane, Facebook i LinkedIn pozostają ręcznym importem. Żądania mają jawnie ograniczoną listę hostów, limit 2 MB i timeout. Każde przekierowanie wraca do wspólnego kolektora do sprawdzenia. Nagłówki, cookies i sesje przeglądarki nie są kopiowane.

Skrypt `node scripts/prepare-ios.mjs` przygotowuje samowystarczalny HTML na Windowsie lub Ubuntu. `node scripts/build-ios.mjs` na Macu z Xcode generuje projekt, buduje aplikację na urządzenie i tworzy `build/ios/TechRadar-unsigned.ipa`. Wstępny cel: iOS 18 lub nowszy. Ikony iOS, zachowanie systemowego importu plików, zgłaszanie błędów eksportu, trwałość danych przy odnowieniu i dostęp do źródeł wymagają weryfikacji na urządzeniu po pierwszej kompilacji.

Na Windowsie przeszło 20 testów logiki i `scripts/check-ios-ui.mjs`: samowystarczalny HTML otwarty w Chromium, zapis/odtworzenie przez testowy most, eksport ICS i JSON, import publicznego źródła, odrzucanie obcych adresów oraz zachowanie zapisanych wydarzeń po awarii kolektora. Nie jest to test kodu Swift, Safari ani iPhone'a. Skrypt testowy korzysta z opcjonalnego Playwright (`PLAYWRIGHT_MODULE`, `BROWSER_CHANNEL`).

## Bez dodatkowych opłat

Workflow jest uruchamiany ręcznie i ma warunek blokujący job na prywatnych repozytoriach. Obecne repozytorium pozostaje prywatne, więc runner nie zostanie uruchomiony. Nie zmieniono budżetów GitHuba i nie uruchomiono płatnych usług.

Opcja publiczna: standardowy runner macOS w GitHub Actions jest bezpłatny według aktualnej dokumentacji. Publikacja kodu wymaga decyzji użytkownika. Można stworzyć osobne publiczne repozytorium zawierające tylko oczyszczone źródła budowania, bez historii dotychczasowych repozytoriów. Alternatywa: własny Mac/runner albo zweryfikowany darmowy limit prywatnych Actions z twardym limitem wydatków.

Po udanej kompilacji użytkownik pobiera artefakt, rozpakowuje ZIP i podpisuje IPA w SideStore na własnym iPhonie. Instalację SideStore można przygotować na Windowsie/Ubuntu. Nie przekazuj hasła Apple Account ani pliku parowania do repozytorium lub tej rozmowy. SideStore zajmuje jeden z trzech slotów; Radar oraz Focus Tube mogą zająć pozostałe. Odnawianie przed upływem 7 dni jest nadal konieczne.

## Źródła

- https://docs.sidestore.io/docs/installation/prerequisites
- https://docs.sidestore.io/docs/installation/install
- https://docs.sidestore.io/docs/faq
- https://developer.apple.com/help/account/basics/about-your-developer-account
- https://docs.github.com/en/billing/concepts/product-billing/github-actions
