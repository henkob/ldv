# Ladda upp syntetiska porträtt till LDV-test

Den här rutinen gäller **endast** Supabase-projektet `wtrrdxurgxyvfahhgbsh` (ldv-test).

## Förutsättningar
- Använd ett befintligt **testadministratörskonto**, aldrig ett produktionskonto.
- Kör i en webbsida där en Supabase-klient är autentiserad mot **ldv-test**.
- Filen `prototypes/seed-zoo-test-portraits.mjs` innehåller den skyddade funktionen `seedZooPortraits`.
- Den kontrollerar både angiven projekt-URL och klientens faktiska Supabase-URL, adminstatus och att exakt 84 syntetiska personer finns.
- Bildformatet är PNG, vilket stöds av den privata bucketen `ldv-avatars`.

## Körning
Importera modulen i ett webbläsarsammanhang där du redan har den autentiserade Supabase-klienten:
```js
import { seedZooPortraits } from './prototypes/seed-zoo-test-portraits.mjs';
const result = await seedZooPortraits(testSupabaseClient, {
  projectUrl: 'https://wtrrdxurgxyvfahhgbsh.supabase.co'
});
console.log(result);
```
`testSupabaseClient` måste vara den inloggade klienten för ldv-test. Ingen nyckel ska klistras in i källkoden. Modulen ska **inte** köras i produktionsappen.

## Verifiering
Kör följande SQL i **ldv-test** efter uppladdningen:
```sql
select count(*) as synthetic_portrait_objects
from storage.objects o
join public.people p on
  split_part(o.name, '/', 1) = p.id::text
where o.bucket_id = 'ldv-avatars'
  and p.email like 'ldv-zoo-test-%@example.invalid'
  and split_part(o.name, '/', 2) in ('avatar','avatar-full');
```
Förväntat resultat: **168** (84 deltagare × 2 varianter).

Verifiera också med en **inloggad testdeltagare** att signerade URL:er fungerar för en annan bekräftad resenär. Kontrollera mobil, desktop, stor bild, bildbeskärning och att oinloggade inte får åtkomst. Databasens SQL-kontroll ersätter inte det funktionella behörighetstestet.

## Status
- Syntetiska deltagare: 84, skapade i ldv-test.
- Storage-regler: åtta, anpassade till produktionsmodellen.
- Uppladdningsskript: klart i utvecklingsgrenen.
- Faktisk uppladdning och webbläsartest: **inte genomförda**.
- Produktion: **orörd**.
