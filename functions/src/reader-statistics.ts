/** Read-only aggregate reports. Never accepts account/property IDs or credentials from clients. */
import {GoogleAuth} from 'google-auth-library';
import {getFirestore} from 'firebase-admin/firestore';
import {getStorage} from 'firebase-admin/storage';
import {createPrivateKey, sign} from 'node:crypto';
import {gunzipSync} from 'node:zlib';
import {ApiError} from './content';

type Row = Record<string,string|number>;
export type Report = {label:string;rows:Row[];note?:string};
export type StatsResult = {source:string;status:'ready'|'setup'|'error';message?:string;start:string;end:string;fetchedAt:string;cached?:boolean;reports:Record<string,Report>};
export function statsRange(days:unknown, now=new Date()) {
  if (!['7','28'].includes(String(days))) throw new ApiError(400,'기간은 7일 또는 28일로 선택해 주세요.');
  // Use completed dates in Korea. Source-native store dates are preserved, not shifted.
  const end=new Date(Date.UTC(now.getUTCFullYear(),now.getUTCMonth(),now.getUTCDate()));
  const korea=new Date(now.getTime()+9*3600000);end.setTime(Date.UTC(korea.getUTCFullYear(),korea.getUTCMonth(),korea.getUTCDate())-86400000);
  const start=new Date(end.getTime()-(Number(days)-1)*86400000);
  return {start:start.toISOString().slice(0,10),end:end.toISOString().slice(0,10)};
}
export function parseDelimited(text:string,delimiter=','):Record<string,string>[] {
  const rows:string[][]=[];let row:string[]=[],cell='',quoted=false;
  text=text.replace(/^\uFEFF/,'');
  for(let i=0;i<text.length;i++) {const c=text[i];
    if(c==='"'){if(quoted&&text[i+1]==='"'){cell+='"';i++;}else quoted=!quoted;}
    else if(c===delimiter&&!quoted){row.push(cell);cell='';}
    else if((c==='\n'||c==='\r')&&!quoted){if(c==='\r'&&text[i+1]==='\n')i++;row.push(cell);if(row.some(Boolean))rows.push(row);row=[];cell='';}
    else cell+=c;
  }
  if(quoted)throw new Error('invalid_report');
  if(cell||row.length){row.push(cell);rows.push(row);}
  const headers=rows.shift()||[];
  return rows.map(r=>Object.fromEntries(headers.map((h,i)=>[h,r[i]||''])));
}
export function reportText(bytes:Buffer) {
  if(bytes[0]===0xff&&bytes[1]===0xfe)return bytes.subarray(2).toString('utf16le');
  return bytes.toString('utf8');
}
export function aggregatePlay(rows:Record<string,string>[],start:string,end:string) {
  const daily:Row[]=[],countries=new Map<string,number>();
  for(const r of rows){if(r['Package Name']!=='com.koofylab.koofyreader'||r.Date<start||r.Date>end)continue;
    const value=Number(r['Daily User Installs']);if(!r['Daily User Installs']?.trim()||!Number.isFinite(value))throw new Error('invalid_report');
    if('Country' in r)countries.set(r.Country,(countries.get(r.Country)||0)+value);
    else daily.push({date:r.Date,installs:value,uninstalls:Number(r['Daily User Uninstalls'])||0});
  }
  return {daily,countries:[...countries].map(([country,installs])=>({country,installs})).sort((a,b)=>b.installs-a.installs)};
}
export function aggregateApple(rows:Record<string,string>[],date:string):Row[] {
  const countries=new Map<string,number>();
  for(const r of rows){if(r['Apple Identifier']!=='6814514729'||!['1','1F','1T'].includes(r['Product Type Identifier']))continue;
    const units=Number(r.Units);if(!r.Units?.trim()||!Number.isFinite(units))throw new Error('invalid_report');
    countries.set(r['Country Code'],(countries.get(r['Country Code'])||0)+units);
  }
  return [...countries].map(([country,downloads])=>({date,country,downloads}));
}
class UpstreamError extends Error {constructor(readonly code:number){super('upstream');}}
const auth=new GoogleAuth({scopes:['https://www.googleapis.com/auth/analytics.readonly','https://www.googleapis.com/auth/devstorage.read_only','https://www.googleapis.com/auth/cloud-platform']});
async function google(url:string,body?:unknown) {
  const client=await auth.getClient();
  const result=await client.request({url,method:body?'POST':'GET',data:body,timeout:20000});return result.data as Record<string,any>;
}
function failure(error:unknown):string {
  const code=error instanceof UpstreamError?error.code:(error as {response?:{status?:number}})?.response?.status;
  if(code===401||code===403)return '조회 권한 또는 API 사용 설정을 확인해 주세요. 동의 설정을 변경할 필요는 없습니다.';
  if(code===429)return '조회 한도에 도달했습니다. 잠시 후 다시 시도해 주세요.';
  return '공급자 보고서를 가져오지 못했습니다. 인증 설정과 제공 지연을 확인해 주세요.';
}
export async function analyticsReports(start:string,end:string,platform:string):Promise<Record<string,Report>> {
  const property=process.env.READER_GA_PROPERTY_ID||'555135756';
  if(!/^\d+$/.test(property))throw new Error('invalid_property');
  const root=`https://analyticsdata.googleapis.com/v1beta/properties/${property}`;
  const metadata=await google(root+'/metadata');
  const dimensions=new Set((metadata.dimensions||[]).map((d:any)=>d.apiName));
  const metrics=new Set((metadata.metrics||[]).map((m:any)=>m.apiName));
  const filters:any[]=[{filter:{fieldName:'platform',inListFilter:{values:platform==='all'?['Android','iOS']:[platform]}}}];
  const run=async(dims:string[],mets:string[],event?:string,limit='100')=>{
    const expressions=[...filters,...(event?[{filter:{fieldName:'eventName',stringFilter:{matchType:'EXACT',value:event}}}]:[])];
    const r=await google(root+':runReport',{dateRanges:[{startDate:start,endDate:end}],dimensions:dims.map(name=>({name})),metrics:mets.map(name=>({name})),dimensionFilter:{andGroup:{expressions}},orderBys:dims.length?(dims.includes('date')?[{dimension:{dimensionName:'date'}}]:[{metric:{metricName:mets[0]},desc:true}]):undefined,limit});
    const rows=(r.rows||[]).map((row:any)=>Object.fromEntries([...dims.map((name,i)=>[name,row.dimensionValues?.[i]?.value||'']),...mets.map((name,i)=>[name,Number(row.metricValues?.[i]?.value)||0])]));
    return {rows,note:r.metadata?.subjectToThresholding?'소수 사용자 보호를 위한 기준점이 적용될 수 있습니다.':Number(r.rowCount)>Number(limit)?`상위 ${limit}개 항목입니다.`:undefined};
  };
  const definitions:[string,string,string[],string[]][]=[
    ['summary','앱 사용 요약',[],['activeUsers','newUsers','sessions','userEngagementDuration']],
    ['daily','날짜별 활동',['date'],['activeUsers','newUsers']],
    ['countries','국가별 사용자',['country'],['activeUsers','newUsers']],
    ['platforms','플랫폼별 사용자',['platform'],['activeUsers','newUsers','sessions']],
    ['versions','앱 버전',['platform','appVersion'],['activeUsers']],
    ['events','기능별 사용',['eventName'],['eventCount','totalUsers']],
  ];
  const reports:Record<string,Report>={};
  // Limit concurrency and never add daily unique users to invent a period total.
  for(let i=0;i<definitions.length;i+=3)await Promise.all(definitions.slice(i,i+3).map(async([key,label,d,m])=>{reports[key]={label,...await run(d,m)};}));
  reports.downloads={label:'도서·글꼴 다운로드',rows:[],note:'result·content_type 이벤트 맞춤 측정기준 등록 후 성공·실패를 구분할 수 있습니다. 등록 전 데이터는 소급되지 않습니다.'};
  if(dimensions.has('customEvent:result')&&dimensions.has('customEvent:content_type'))reports.downloads={label:'도서·글꼴 다운로드',...await run(['customEvent:content_type','customEvent:result'],['eventCount'],'catalog_download')};
  reports.reading={label:'독서 시간',rows:[],note:'seconds 이벤트 맞춤 측정항목(단위: 초) 등록이 필요합니다. 앱 참여 시간과 독서 시간은 다릅니다.'};
  if(metrics.has('customEvent:seconds'))reports.reading={label:'독서 시간',...await run(['date'],['customEvent:seconds'],'reading_time')};
  return reports;
}
async function playReports(start:string,end:string):Promise<Record<string,Report>> {
  const bucket=process.env.READER_PLAY_REPORT_BUCKET||'';
  if(!/^pubsite_prod_(?:rev_)?\d+$/.test(bucket))throw new Error('invalid_bucket');
  const months=new Set<string>();for(let day=start;day<=end;day=new Date(Date.parse(day+'T00:00:00Z')+86400000).toISOString().slice(0,10))months.add(day.slice(0,7).replace('-',''));
  const all:Record<string,string>[]=[];let missing=0;
  for(const month of months)for(const suffix of ['overview','country']) {
    const name=`stats/installs/installs_com.koofylab.koofyreader_${month}_${suffix}.csv`;
    try {const file=getStorage().bucket(bucket).file(name);const [info]=await file.getMetadata();if(Number(info.size)>20*1024*1024)throw new Error('large_report');const [bytes]=await file.download();if(bytes.length>20*1024*1024)throw new Error('large_report');all.push(...parseDelimited(reportText(bytes)));}
    catch(error){if((error as {code?:number}).code===404){missing++;continue;}throw error;}
  }
  const result=aggregatePlay(all,start,end);
  const note='Google Play 보고서 날짜 기준. 통계 파일은 보통 3~7일 지연되며, 일별 사용자 설치는 재설치를 포함할 수 있어 최초 다운로드와 다릅니다.'+(missing?' 일부 월별 보고서는 아직 제공되지 않았습니다.':'');
  return {daily:{label:'Google Play 사용자 설치',rows:result.daily,note},countries:{label:'국가별 사용자 설치',rows:result.countries,note}};
}
async function appleReports(start:string,end:string):Promise<Record<string,Report>> {
  // Secret Manager reference only. Never store a P8 private key in environment files or Firestore.
  const secret=process.env.READER_APPLE_KEY_SECRET||'';
  if(!/^projects\/koofy-reader\/secrets\/[a-zA-Z0-9_-]+\/versions\/(latest|\d+)$/.test(secret))throw new Error('invalid_secret');
  const keyResponse=await google(`https://secretmanager.googleapis.com/v1/${secret}:access`);
  const key=Buffer.from(keyResponse.payload.data,'base64').toString();
  const now=Math.floor(Date.now()/1000),header=Buffer.from(JSON.stringify({alg:'ES256',kid:process.env.READER_APPLE_KEY_ID,typ:'JWT'})).toString('base64url');
  const claims=Buffer.from(JSON.stringify({iss:process.env.READER_APPLE_ISSUER_ID,iat:now,exp:now+600,aud:'appstoreconnect-v1'})).toString('base64url');
  const input=header+'.'+claims,signature=sign('sha256',Buffer.from(input),{key:createPrivateKey(key),dsaEncoding:'ieee-p1363'}).toString('base64url');
  const token=input+'.'+signature,days:string[]=[];
  for(let d=start;d<=end;d=new Date(Date.parse(d+'T00:00:00Z')+86400000).toISOString().slice(0,10))days.push(d);
  const rows:Row[]=[],missing:string[]=[],provided=new Set<string>();
  for(let i=0;i<days.length;i+=4)await Promise.all(days.slice(i,i+4).map(async date=>{
    const ref=getFirestore().collection('readerStatisticsCache').doc(`apple_daily_${date}`),cached=await ref.get();
    if(cached.exists&&Date.now()-cached.data()!.at<6*3600000){rows.push(...cached.data()!.rows);provided.add(date);return;}
    const q=new URLSearchParams({'filter[frequency]':'DAILY','filter[reportDate]':date,'filter[reportSubType]':'SUMMARY','filter[reportType]':'SALES','filter[vendorNumber]':process.env.READER_APPLE_VENDOR_NUMBER!,'filter[version]':'1_0'});
    const response=await fetch('https://api.appstoreconnect.apple.com/v1/salesReports?'+q,{headers:{Authorization:`Bearer ${token}`},signal:AbortSignal.timeout(15000)});
    if(response.status===404){missing.push(date);return;}
    if(!response.ok)throw new UpstreamError(response.status);
    const bytes=Buffer.from(await response.arrayBuffer());if(bytes.length>20*1024*1024)throw new Error('large_report');
    const dayRows=aggregateApple(parseDelimited(gunzipSync(bytes,{maxOutputLength:40*1024*1024}).toString('utf8'),'\t'),date);
    rows.push(...dayRows);provided.add(date);await ref.set({at:Date.now(),rows:dayRows});
  }));
  const daily=new Map<string,number>([...provided].map(date=>[date,0])),countries=new Map<string,number>();
  for(const r of rows){daily.set(String(r.date),(daily.get(String(r.date))||0)+Number(r.downloads));countries.set(String(r.country),(countries.get(String(r.country))||0)+Number(r.downloads));}
  const note='Apple Sales and Trends 앱 판매 수량(신규 앱 유형 1·1F·1T). 업데이트·재다운로드·인앱결제 제외. App Analytics 최초 다운로드와 집계 기준이 다를 수 있습니다.'+(missing.length?` 보고서 미제공 ${missing.length}일: 0건으로 간주하지 않습니다.`:'');
  return {daily:{label:'Apple 신규 앱 수량',rows:[...daily].sort().map(([date,downloads])=>({date,downloads})),note},countries:{label:'국가별 신규 앱 수량',rows:[...countries].map(([country,downloads])=>({country,downloads})).sort((a,b)=>b.downloads-a.downloads),note}};
}
const pending=new Map<string,Promise<StatsResult>>();
export async function readerStatistics(source:unknown,days:unknown,platform:unknown):Promise<StatsResult> {
  if(!['analytics','googlePlay','apple'].includes(String(source))||!['all','Android','iOS'].includes(String(platform)))throw new ApiError(400,'올바른 통계 종류와 플랫폼을 선택해 주세요.');
  const range=statsRange(days),result:StatsResult={source:String(source),status:'ready',...range,fetchedAt:new Date().toISOString(),reports:{}};
  if(source==='googlePlay'&&!process.env.READER_PLAY_REPORT_BUCKET)return {...result,status:'setup',message:'Play Console 보고서 버킷과 서비스 계정의 보고서 조회 권한을 연결해 주세요.'};
  if(source==='apple'&&!['READER_APPLE_KEY_SECRET','READER_APPLE_KEY_ID','READER_APPLE_ISSUER_ID','READER_APPLE_VENDOR_NUMBER'].every(k=>process.env[k]))return {...result,status:'setup',message:'App Store Connect 보고서 API 키·발급자 ID·공급업체 번호를 연결해 주세요. APNs 푸시 키는 사용할 수 없습니다.'};
  const cacheKey=`v2_${source}_${range.start}_${range.end}_${source==='analytics'?platform:'all'}`;
  if(pending.has(cacheKey))return pending.get(cacheKey)!;
  const task=(async()=>{
    const ref=getFirestore().collection('readerStatisticsCache').doc(cacheKey);const cached=await ref.get();
    if(cached.exists&&Date.now()-cached.data()!.at<30*60000)return {...cached.data()!.result,cached:true} as StatsResult;
    try {result.reports=source==='analytics'?await analyticsReports(range.start,range.end,String(platform)):source==='googlePlay'?await playReports(range.start,range.end):await appleReports(range.start,range.end);await ref.set({at:Date.now(),result:JSON.parse(JSON.stringify(result))});return result;}
    catch(error){return {...result,status:'error' as const,message:failure(error)};}
  })();pending.set(cacheKey,task);try{return await task;}finally{pending.delete(cacheKey);}
}
