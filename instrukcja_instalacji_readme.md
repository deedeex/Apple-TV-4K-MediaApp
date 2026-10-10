# Jak zainstalować aplikację na własnym Apple TV za pomocą Xcode

Ponieważ aplikacja nie jest dystrybuowana przez App Store ani TestFlight, jej kompilacja i instalacja wymaga użycia programu **Xcode** oraz własnego (darmowego) konta Apple ID. 

Instalacja zajmuje około 5 minut i sprowadza się do kilku prostych kroków konfiguracyjnych.

---

## Wymagania wstępne

* Komputer Mac z zainstalowanym programem **Xcode** (dostępny bezpłatnie w Mac App Store).
* Urządzenie **Apple TV** podłączone do tej samej sieci Wi-Fi co Mac.
* Własne konto Apple ID.

---

## Instrukcja krok po kroku

### 1. Pobierz projekt
Pobierz kod źródłowy z repozytorium (lub sklonuj je za pomocą Git) i otwórz plik `.xcodeproj` lub `.xcworkspace` w programie Xcode.

### 2. Dodaj swoje konto Apple ID w Xcode
1. W programie Xcode otwórz menu górne: **Xcode > Settings** (lub *Preferences*).
2. Przejdź do zakładki **Accounts**.
3. Kliknij przycisk **`+`** w lewym dolnym rogu i dodaj swoje konto Apple ID.

### 3. Zmień Zespół (Team) oraz Bundle Identifier
Ponieważ identyfikatory Apple są przypisane do konkretnego konta deweloperskiego, musisz zmodyfikować dwa ustawienia w projekcie:

1. W nawigatorze po lewej stronie kliknij w główny plik projektu (najwyższy element na liście).
2. Wybierz główny target aplikacji w sekcji **Targets**.
3. Przejdź do zakładki **Signing & Capabilities**.
4. Upewnij się, że opcja **Automatically manage signing** jest zaznaczona.
5. W polu **Team** wybierz swoje konto z listy (zazwyczaj opisane jako `Twoje Imię (Personal Team)`).
6. W polu **Bundle Identifier** zmień domyślny ciąg znaków (np. z `com.tworca.MojaAplikacja`) na własny unikalny tekst (np. `com.twojeimie.MojaAplikacja`).  
   *(Bez tej zmiany Xcode zgłosi błąd braku uprawnień do identyfikatora poprzedniego twórcy).*

### 4. Sparuj Apple TV z Xcode
1. Upewnij się, że komputer Mac oraz Apple TV znajdują się w tej samej sieci Wi-Fi.
2. Na Apple TV przejdź do: **Ustawienia > Piloty i urządzenia > Remotes and Devices > Xcode** (lub *Remote app and devices*).
3. W Xcode na Macu otwórz menu górne: **Window > Devices and Simulators** (skrót `Shift + Cmd + 2`).
4. Na liście urządzeń po lewej stronie wybierz swoje Apple TV i kliknij **Connect**.
5. Wpisz kod PIN wyświetlony na ekranie telewizora, aby dokończyć parowanie.

### 5. Zainstaluj i uruchom aplikację
1. Na górnym pasku Xcode (koło przycisku *Play/Build*) wybierz jako urządzenie docelowe Twoje sparowane **Apple TV**.
2. Kliknij przycisk **Play (Run)** lub wciśnij skrót `Cmd + R`, aby skompilować i wgrać aplikację na telewizor.

---

## Rozwiązywanie problemów & Ważne informacje

### Błąd "Untrusted Developer" / Brak zaufania do certyfikatu
Jeśli przy próbie uruchomienia aplikacji na Apple TV pojawi się komunikat o niezaufanym deweloperze:
1. Na Apple TV przejdź do: **Ustawienia > Ogólne > Profile i zarządzanie urządzeniami** (lub *Profiles & Device Management*).
2. Znajdź swój adres e-mail / profil deweloperski na liście.
3. Wybierz opcję **Zaufaj [Twoje Apple ID]** i zatwierdź wybór.

### Ważność instalacji (7 dni)
Jeśli korzystasz z darmowego konta Apple ID, darmowy certyfikat wygasa po **7 dniach**. Po tym czasie aplikacja przestanie się otwierać na Apple TV. Aby z niej ponownie korzystać, wystarczy podłączyć komputer, otworzyć projekt w Xcode i ponownie kliknąć **Run** (`Cmd + R`).