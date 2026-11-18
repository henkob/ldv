/**
 * Copies only first names, nicknames and private portrait files from LDV production
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
  production.rpc('ldv_admin_people').select('id,first_name,nickname'),
  test.rpc('ldv_admin_people').select('id,email').like('email','ldv-zoo-test-%@example.invalid')
 ]);
 if(srcRes.error) throw srcRes.error;
 if(dstRes.error) throw dstRes.error;
 const dest=dstRes.data.filter(p=>/^ldv-zoo-test-\d{3}@example\.invalid$/.test(p.email||''))
  .sort((a,b)=>a.email.localeCompare(b.email));
 if(dest.length!==84) throw Error('Expected 84 synthetic destination records');
 // Do not use the current trip participants blindly: only confirmed 2027 trip members.
 const {data:participants,error:participantsError}=await production
  .rpc('ldv_admin_participants',{p_trip_id:2}).select('person_id').eq('status','confirmed');
 if(participantsError) throw participantsError;
 const allowed=new Set(participants.map(x=>x.person_id));
 const src=srcRes.data.filter(p=>allowed.has(p.id))
  .sort((a,b)=>a.id.localeCompare(b.id));
 const storageSrc=production.storage.from('ldv-avatars');
 const storageDst=test.storage.from('ldv-avatars');
 const available=[];
 for(const person of src){
  if(!person.first_name?.trim()) continue;
  for(const suffix of ['avatar-full','avatar']){
   const {data,error}=await storageSrc.download(person.id+'/'+suffix);
   if(error) continue;
   if(data?.size && /^image\/(jpeg|png|webp)$/i.test(data.type)){
    const image=await createImageBitmap(data).catch(()=>null);
    if(!image) continue;
    const canvas=document.createElement('canvas');
    const scale=Math.min(1,640/Math.max(image.width,image.height));
    canvas.width=Math.max(1,Math.round(image.width*scale));
    canvas.height=Math.max(1,Math.round(image.height*scale));
    canvas.getContext('2d').drawImage(image,0,0,canvas.width,canvas.height);
    image.close();
    // Re-encode so filenames and embedded EXIF cannot reveal the answer.
    const blob=await new Promise(resolve=>canvas.toBlob(resolve,'image/jpeg',0.9));
    if(!blob) continue;
    available.push({person,blob,key:crypto.randomUUID()});
    break;
   }
  }
 }
 if(available.length<14) throw Error('At least 14 readable source portraits required');
 let completed=0;
 for(const [index,target] of dest.entries()){
  const {person,blob,key}=available[index%available.length];
  const path='zoo/'+crypto.randomUUID();
  const {error}=await storageDst.upload(path,blob,{contentType:blob.type});
  if(error) throw error;
  const verified=await storageDst.download(path);
  if(verified.error || verified.data.size!==blob.size) throw Error('Test portrait verification failed');
  const picture=await createImageBitmap(verified.data);
  picture.close();
  const {error:registerError}=await test.rpc('ldv_zoo_register_portrait',{
   p_slot:target.id,p_photo_path:path,p_portrait_key:key,
   p_first_name:person.first_name,p_nickname:person.nickname
  });
  if(registerError) throw registerError;
  onProgress({completed:++completed,total:dest.length});
 }
 return {completed,uniquePortraits:Math.min(available.length,dest.length)};
}
