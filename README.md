# Osobiste aplikacje iPhone

Przygotowany do przeglądu pakiet źródeł: Focus Tube (własne rozszerzenie Safari) i Warsaw Tech Radar (aplikacja z lokalnym interfejsem). Bez historii prywatnych repozytoriów, konfiguracji hostingu, haseł, certyfikatów, plików parowania i danych preferencji. Dołączone wydarzenia są odczytem publicznych źródeł.

Stan 21.10.2026: publikacja wybranych źródeł zaakceptowana przez właściciela. Pierwsza kompilacja Xcode pozostaje do wykonania. Testy JavaScript i interfejsu na Windowsie przeszły; nie potwierdzają działania kodu iOS.

W GitHub Actions uruchom ręcznie Build personal iPhone apps. Workflow używa standardowego macos-15 i blokuje się w repozytorium prywatnym. Nie potrzebuje Apple ID ani certyfikatów. Artefakty IPA są przechowywane przez jeden dzień.

Gotowe IPA podpisuje użytkownik w SideStore na własnym iPhonie. Instalacja SideStore z Windowsa/Ubuntu: https://docs.sidestore.io/docs/installation/prerequisites . Limit darmowego konta i odnawianie co 7 dni nadal obowiązują. Szczegóły każdej aplikacji w apps/<nazwa>/docs/IPHONE_SIDELOAD.md.

Kompilacja każdej aplikacji lokalnie na Macu z Xcode: przejść do apps/<nazwa> i uruchomić node scripts/build-ios.mjs. Nie korzystać z firmowego komputera bez zgody firmy.
