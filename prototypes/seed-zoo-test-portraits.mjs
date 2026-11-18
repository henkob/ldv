/**
 * Seed synthetic LDV test portraits through the normal Supabase Storage API.
 * Run ONLY against ldv-test, with an authenticated test administrator.
 * Usage in browser console after importing Supabase client:
 *   await seedZooPortraits(supabaseClient, {projectUrl:'https://wtrrdxurgxyvfahhgbsh.supabase.co'})
 * This helper does not contain keys, real people or production data.
 */
export async function seedZooPortraits(client,{projectUrl}={}){
 const expected='https://wtrrdxurgxyvfahhgbsh.supabase.co';
 if(projectUrl!==expected) throw new Error('Refusing to seed outside ldv-test');
 const {data:admin,error:adminError}=await client.rpc('ldv_is_admin');
 if(adminError||admin!==true) throw new Error('Authenticated test admin required');
 const {data:rows,error}=await client.rpc('ldv_admin_people');
 if(error) throw error;
 const synthetic=rows.filter(p=>/^ldv-zoo-test-\\d{3}@example\\.invalid$/.test(p.email||''));\n if(synthetic.length!==84) throw new Error('Expected exactly 84 synthetic test people');
 const storage=client.storage.from('ldv-avatars');
 let completed=0;
 for(const [index,p] of synthetic.entries()){
  // Original illustrated test portraits: deterministic distinct shapes and colors.
  const hue=(index*137.508)%360;
  const hairHue=(hue+70)%360;
  const skin=['#e4b48e','#b97751','#f2cfab','#8c563f','#d79a70'][index%5];
  const hair=['#2c1c19','#5e3826','#b47d36','#28282d','#9a5033'][index%5];
  const glasses=index%4===0?'<g fill="none" stroke="#24324b" stroke-width="6"><circle cx="168" cy="202" r="29"/><circle cx="252" cy="202" r="29"/><path d="M197 198h26"/></g>':'';
  const beard=index%3===0?'<path d="M160 251q50 90 100 0q-50 46-100 0" fill="'+hair+'" opacity=".7"/>':'';
  const svg='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 420 420"><rect width="420" height="420" fill="hsl('+hue+' 45% 68%)"/><circle cx="210" cy="208" r="174" fill="hsl('+hairHue+' 32% 80%)"/><path d="M62 420q20-116 148-116t148 116" fill="hsl('+hue+' 56% 34%)"/><ellipse cx="210" cy="205" rx="104" ry="128" fill="'+skin+'"/><path d="M103 188q-8-129 107-132 116 0 107 132-32-45-56-57-70 52-158 57" fill="'+hair+'"/><ellipse cx="171" cy="211" rx="9" ry="11" fill="#26232b"/><ellipse cx="250" cy="211" rx="9" ry="11" fill="#26232b"/><path d="M210 219l-12 37h25" fill="none" stroke="#915b43" stroke-width="5" stroke-linecap="round"/><path d="M173 276q37 26 74 0" fill="none" stroke="#8e443d" stroke-width="7" stroke-linecap="round"/>'+beard+glasses+'</svg>';
  for(const path of [p.id+'/avatar',p.id+'/avatar-full']){
   const {error:uploadError}=await storage.upload(path,new Blob([svg],{type:'image/svg+xml'}),{contentType:'image/svg+xml',upsert:true});
   if(uploadError) throw new Error('Upload failed at '+path+': '+uploadError.message);
  }
  completed++;
 }
 return {completed,uploadedObjects:completed*2};
}
