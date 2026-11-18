/**
 * Copies ONLY real first names, nicknames and private portrait files from LDV production
 * into 84 EXISTING synthetic test records. No production writes and no real email copied.
 * Both clients must already be signed in as administrators in their respective projects.
 * Run in an authenticated browser with the two Supabase clients passed explicitly.
 */
export async function copyZooPortraitsFromProduction(production,test,{onProgress=()=>{}}={}){
 const PROD='https://hoisvaisfeptkdwmdlmg.supabase.co';
 const TEST='https://wtrrdxurgxyvfahhgbsh.supabase.co';
 if(production?.supabaseUrl?.replace(/\/$/,'')!==PROD || test?.supabaseUrl?.replace(/\/$/,'')!==TEST)
  throw Error('Project mismatch: copy refused');
 for(const [label,client] of [['production',production],['test',test]]){
  const {data,error}=await client.rpc('ldv_is_admin');
  if(error||data!==true) throw Error(label+' administrator login required');
 }
 const [srcRes,dstRes]=await Promise.all([
  production.rpc('ldv_admin_people'),test.rpc('ldv_admin_people')
 ]);
 if(srcRes.error) throw srcRes.error;
 if(dstRes.error) throw dstRes.error;
 const dest=dstRes.data.filter(p=>/^ldv-zoo-test-\d{3}@example\.invalid$/.test(p.email||''))
  .sort((a,b)=>a.email.localeCompare(b.email));
 if(dest.length!==84) throw Error('Expected 84 synthetic destination records');
 // Do not use the current trip participants blindly: only confirmed 2027 trip members.
 const {data:participants,error:participantsError}=await production
  .from('trip_participation').select('person_id').eq('trip_id',2).eq('status','confirmed');
 if(participantsError) throw participantsError;
 const allowed=new Set(participants.map(x=>x.person_id));
 const src=srcRes.data.filter(p=>allowed.has(p.id))
  .sort((a,b)=>a.id.localeCompare(b.id));
 const storageSrc=production.storage.from('ldv-avatars');
 const storageDst=test.storage.from('ldv-avatars');
 let completed=0,skipped=[];
 for(let i=0;i<Math.min(src.length,dest.length);i++){
  const person=src[i],target=dest[i];
  // Try the original full-size portrait first; only copy a real file.
  let blob=null;
  for(const suffix of ['avatar-full','avatar']){
   const {data,error}=await storageSrc.download(person.id+'/'+suffix);
   if(!error && data){blob=data;break;}
  }
  if(!blob){skipped.push(person.id);continue;}
  // Preserve synthetic email to avoid importing personal contact data.
  const {error:updateError}=await test.rpc('ldv_admin_update_person',{
   p_person_id:target.id,p_first_name:person.first_name,p_last_name:person.last_name,
   p_nickname:person.nickname||'',p_email:target.email,p_phone:null,
   p_who_is_who:null,p_helmet_color:null,p_jacket_color:null,
   p_pants_color:null,p_allergies:null
  });
  if(updateError) throw Error('Test name update failed: '+updateError.message);
  for(const suffix of ['avatar','avatar-full']){
   const {error}=await storageDst.upload(target.id+'/'+suffix,blob,{
    contentType:blob.type||'image/jpeg',upsert:true
   });
   if(error) throw Error('Test portrait upload failed: '+error.message);
  }
  completed++;
  onProgress({completed,total:Math.min(src.length,dest.length),skipped:skipped.length});
 }
 return {completed,uploadedObjects:completed*2,skippedSourceIds:skipped,
  note:'Only test records changed; no production writes.'};
}
