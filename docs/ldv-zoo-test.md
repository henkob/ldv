# Who is Who in the Zoo? i LDV-test

Testvyn finns i menyn i `test.html` på grenen `feature/who-is-who-zoo`.
Sidan använder testprojektet `wtrrdxurgxyvfahhgbsh`. Produktionsappen
publiceras från `main` via GitHub Pages.

## Testdata och start

1. Applicera quizets test-SQL i ordningen schema, privata porträtt,
   förbered omgångar, läs omgångar och spara svar.
2. Kör `copyZooPortraitsFromProduction` med autentiserade administratörsklienter
   för produktion och test. Funktionen läser produktionslagringen, tar bort
   bildmetadata vid omkodning och verifierar testfilerna efter uppladdning.
   Den kopierar förnamn och eventuellt smeknamn. Testposternas adresser är syntetiska.
3. Kör `ldv_zoo_prepare_test_rounds` i testprojektet med `p_first_day`
   satt till `2026-11-19`. Den skapar sex omgångar med 14 verifierade
   porträtt vardera. Omgångarna öppnar vid midnatt svensk tid den 19–24
   november. Tävlingen stänger vid midnatt den 25 november.

Porträtten ligger i den privata bucketen `ldv-avatars` under slumpmässiga
quizsökvägar. Porträttmappningen har inga läsrättigheter för deltagare.
Quizets API lämnar ut facit först efter att svaret sparats. Smeknamn,
diakritiska tecken och ett enstaka skrivfel i namn på minst fem tecken
hanteras av servern.

Kör `node prototypes/zoo-rounds.test.mjs` för prototypens rundtester.
Verifiera även inloggning och bildläsning i testappen med ett deltagarkonto.
