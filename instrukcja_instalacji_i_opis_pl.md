# Pingu Player – Odtwarzacz mediów dla Apple TV (tvOS)

**Pingu Player** to dedykowana aplikacja na Apple TV (tvOS) do bezpośredniego przeglądania zdjęć oraz odtwarzania filmów przechowywanych na domowym serwerze NAS (np. Synology) z wykorzystaniem protokołu SMB.

Aplikacja działa bezpośrednio na plikach udostępnionych w sieci lokalnej – bez konieczności korzystania z usługi iCloud oraz bez wymogu importowania czegokolwiek do systemowej biblioteki Zdjęć.

---

## 🌟 Możliwości i funkcje aplikacji

### 🎨 Interfejs, Siatka Kafelków i Design (UI/UX)
* **Nowoczesny wygląd Liquid Glass:** Elementy interfejsu wykorzystują natywne efekty przezroczystości i rozmycia szkła (*Liquid Glass / Materials*), zapewniając spójność z najnowszym systemem tvOS.
* **Siatka kafelków (Grid View):** Multimedia wyświetlane są w przejrzystej siatce kafelków, zoptymalizowanej pod kątem szybkiego przeglądania dużych zbiorów.
* **Natywna obsługa pilota Siri Remote:** Płynna nawigacja po kafelkach i menu przy użyciu zarówno gestów (swipe/touchpad), jak i tradycyjnych kliknięć.
* **Cztery główne zakładki:** *Wszystko*, *Zdjęcia*, *Wideo* oraz *Ustawienia*.

### 🗂️ Nawigacja i Boczny Panel Osi Czasu
* **Dedykowany lewy panel (Oś czasu):** Po lewej stronie ekranu znajduje się wygodna kolumna z podziałem na lata i miesiące.
* **Szybki skok do okresu:** Wybór konkretnego miesiąca z lewej kolumny natychmiast przewija siatkę multimediów do wskazanego przedziału czasowego.

### 🎬 Odtwarzanie i podgląd na pełnym ekranie
* **Chronologiczne przeglądanie:** Płynne przechodzenie pilotem między zdjęciami, materiałami Live Photo oraz plikami wideo.
* **Obsługa Live Photo:** Odtwarzanie animacji poprzez jedno kliknięcie środkowego przycisku pilota.
* **Odtwarzanie Wideo (w tym 4K HDR):** Błyskawiczny start (ok. 1 sekundy) dzięki strumieniowaniu na żywo z serwera NAS zamiast pobierania całego pliku na urządzenie.
* **Wygodne sterowanie po seansie:** Po zakończeniu odtwarzania wideo pojawiają się przyciski *„Poprzednie”*, *„Odtwórz ponownie”* oraz *„Następne”*.

### ⚡ Wydajność i dwupoziomowy Cache (100k+ plików)
* **Natychmiastowy start:** Aplikacja po uruchomieniu od razu wyświetla zapamiętaną listę plików, a synchronizację i odświeżanie wykonuje w tle.
* **Zaawansowany dwupoziomowy cache (RAM + Dysk):** Zarówno miniatury, jak i przygotowane pliki multimedialne korzystają z dwupoziomowej pamięci podręcznej (szybka pamięć RAM oraz lokalny dysk Apple TV). Zapobiega to ponownemu pobieraniu tych samych danych z serwera NAS i zapewnia płynne przeglądanie nawet przy ponad 100 000 plików.
* **Pre-loading (wyprzedzające ładowanie):** Sąsiednie zdjęcia i multimedia są przygotowywane w tle, zapewniając błyskawiczne otwieranie przy przełączaniu.

### ⚙️ Konfiguracja i Zarządzanie (Ustawienia)
* **Podgląd i obsługa serwera:** Możliwość podglądu danych połączonego serwera NAS, ręcznego odświeżenia biblioteki oraz usunięcia pamięci podręcznej (czyszczenie cache).
* **Pełna konfiguracja połączenia:** Edycja hosta, nazwy udziału (share), danych użytkownika oraz ścieżki do folderu ze zdjęciami.
* **Personalizacja:** Wybór języka interfejsu (polski, angielski) oraz zmiana tła aplikacji.

---

## 🚀 Instrukcja instalacji i uruchomienia

Ponieważ aplikacja nie jest dystrybuowana przez App Store, jej zbudowanie i instalacja wymagają użycia programu **Xcode** oraz własnego (darmowego) konta Apple ID.

Proces instalacji zajmuje około 5 minut i sprowadza się do kilku prostych kroków konfiguracji.

---

### Wymagania wstępne

* Komputer **Mac** z zainstalowanym programem **Xcode** (dostępny bezpłatnie w Mac App Store).
* **Apple TV** połączone z tą samą siecią Wi-Fi / LAN co komputer Mac.
* Bezpłatne **konto Apple ID** zalogowane w Xcode.

---

### Krok 1: Pobranie kodu źródłowego

Sklonuj repozytorium na swój komputer Mac za pomocą Terminala:

```bash
git clone https://github.com/deedeex/Apple-TV-4K-MediaApp.git
```

LUB pobierz archiwum ZIP ze strony GitHub i rozpakuj je na dysku.

---

### Krok 2: Otwarcie projektu w Xcode

1. Przejdź do folderu z pobranym projektem.
2. Kliknij dwukrotnie plik projektu **`MediaApp.xcodeproj`** (lub `MediaApp.xcworkspace`, jeśli występuje), aby otworzyć go w programie Xcode.

---

### Krok 3: Dodanie konta Apple ID w Xcode

Jeśli jeszcze nie dodawałeś swojego konta Apple ID do Xcode:

1. W menu górnym Xcode wybierz: **Xcode** → **Settings...** (lub użyj skrótu `⌘ + ,`).
2. Przejdź do zakładki **Accounts**.
3. Kliknij przycisk **`+`** w lewym dolnym rogu i wybierz **Apple ID**.
4. Zaloguj się swoimi danymi konta Apple ID.

---

### Krok 4: Konfiguracja podpisywania kodu (Signing & Capabilities)

Aby zainstalować aplikację na fizycznym Apple TV, musisz przypisać do niej swój profil deweloperski:

1. W lewym panelu Xcode (Project Navigator) kliknij najwyższy element z nazwą projektu – **`MediaApp`**.
2. W głównej części okna wybierz cel (Target) **`MediaApp`**.
3. Przejdź do zakładki **Signing & Capabilities**.
4. Zaznacz opcję **Automatically manage signing**.
5. W polu **Team** wybierz swoje konto z rozwijanej listy (będzie tam widoczne Twoje imię i nazwisko z dopiskiem *Personal Team*).
6. W polu **Bundle Identifier** zmień domyślny identyfikator na unikalny (np. dodaj swoje inicjały na końcu, np. `com.tworaj.MediaApp.myversion`), aby uniknąć konfliktów identyfikatorów na serwerach Apple.

---

### Krok 5: Parowanie Apple TV z Xcode

Jeśli Twoje Apple TV nie jest jeszcze połączone z Xcode:

1. Upewnij się, że **Apple TV i Mac są połączone z tą samą siecią lokalną**.
2. W Apple TV wejdź w **Ustawienia** → **Piloty i urządzenia** → **Aplikacja Remote i urządzenia**.
3. W Xcode na Macu wybierz z menu górnego: **Window** → **Devices and Simulators** (lub skrót `⇧ + ⌘ + 2`).
4. W zakładce **Devices** po lewej stronie powinno pojawić się Twoje Apple TV. Kliknij przycisk **Pair**.
5. Na ekranie telewizora pojawi się kod PIN – wpisz go w okienku, które wyskoczy w Xcode.

---

### Krok 6: Włączenie Trybu Dewelopera na Apple TV (tvOS 16+)

1. Po sparowaniu urządzenia, na Apple TV wejdź w **Ustawienia** → **Prywatność i ochrona**.
2. Zjedź na sam dół do sekcji **Tryb dewelopera** (*Developer Mode*) i włącz go.
3. Potwierdź chęć restartu urządzenia.
4. Po ponownym uruchomieniu Apple TV potwierdź włączenie trybu dewelopera i podaj kod blokady ekranu (jeśli jest ustawiony).

---

### Krok 7: Wybór urządzenia i uruchomienie (Build & Run)

1. W górnym pasku Xcode (obok przycisku *Play* ▶) kliknij listę docelowych urządzeń.
2. Wybierz z listy swoje fizyczne **Apple TV** (lub *tvOS Simulator*, jeśli chcesz jedynie przetestować aplikację na komputerze).
3. Kliknij przycisk **Run** (ikona ▶ w lewym górnym rogu) lub użyj skrótu **`⌘ + R`**.
4. Xcode skompiluje kod, zainstaluje aplikację na Apple TV i automatycznie ją uruchomi.

---

### Krok 8: Pierwsza konfiguracja połączenia w aplikacji

1. Po uruchomieniu aplikacji na Apple TV przejdź do zakładki **Ustawienia** (*Settings*).
2. Wprowadź dane dostępowe do swojego serwera NAS:
   * **Host / IP:** Adres IP serwera NAS w sieci lokalnej (np. `192.168.1.100`).
   * **Share (Udział):** Nazwa udostępnionego zasobu (np. `photo` lub `home`).
   * **Ścieżka:** Ścieżka do katalogu ze zdjęciami/filmami (opcjonalnie).
   * **Użytkownik i Hasło:** Dane logowania do konta na serwerze NAS z prawami odczytu.
3. Zapisz ustawienia – aplikacja rozpocznie indeksowanie i buforowanie Twoich multimediów!