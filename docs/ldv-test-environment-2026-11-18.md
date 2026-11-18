# LDV testmiljö – avstämning 2026-11-18

## Syfte
Testmiljön ska kunna användas för realistiska tester av LDV-appen och Who is Who in the Zoo utan att kopiera verkliga deltagaruppgifter.

## Genomfört i Supabase ldv-test
- Skapat public.ldv_admin_notes med produktionslik tabellstruktur, foreign key, maxlängd, RLS och fyra adminpolicyer.
- Lagt till 84 syntetiska deltagare för resa 2027 (trip_id 2), med deterministiska UUID och e-post på example.invalid. Deltagarna är tydligt märkta som testpersoner. Ingen produktionsdata kopierades.
- Verifierat totalt 86 personer och 86 resedeltaganden i testmiljön (två fanns sedan tidigare).
- Ingen ändring i produktion.

## Jämförelse
- Åtta publika tabeller i båda miljöerna.
- Gemensamma kolumner och datatyper överensstämmer.
- Båda har privat Storage-bucket ldv-avatars.
- 34 LDV-funktioner i båda miljöerna; 10 skiljer sig i text/hash. Flera skillnader kan vara formatering men vissa är semantiska.
- Exempel: ldv_is_participant i test kräver att app_access_settings.is_open=true, vilket produktionsversionen inte kräver. Funktionen får INTE kopieras blint mellan miljöerna.

## Återstår innan fullständigt funktionstest
- Skapa/lagra syntetiska porträtt i test-bucket ldv-avatars; just nu har de syntetiska deltagarna inga faktiska bilder.
- Testa signerade bild-URL:er med inloggad testanvändare och kontrollera avatar/full-variant och beskärning.
- Kontrollera åtkomststatus och admin/participant-behörigheter med riktiga testkonton.
- Granska de tio avvikande funktionerna samt storage policies och driftsättningskonfiguration.
- Implementera serverbaserad frågetilldelning, försök och poängräkning. Prototypens JS är inte en säker poängmotor.
- Testa och dokumentera en migrationsväg från utvecklingsgren till produktion.

## Rensa syntetisk testdata
Endast i ldv-test och endast efter kontroll: identifiera poster med email LIKE 'ldv-zoo-test-%@example.invalid'. Ta inte bort de två tidigare testpersonerna.

## Säkerhetsnotering
Supabase security advisor rapporterar befintliga varningar för SECURITY DEFINER-funktioner och RLS utan policies. Ändra inte existerande åtkomstregler utan att först granska funktionernas användning och verifiera avsiktlig behörighetsmodell.
