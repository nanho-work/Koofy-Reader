import test from 'node:test';
import assert from 'node:assert/strict';
import {aggregateApple,aggregatePlay,parseDelimited,reportText,statsRange} from '../src/reader-statistics';
test('completed KST dates include exactly 7/28 days across month boundary',()=>{
 assert.deepEqual(statsRange('7',new Date('2026-11-05T16:00:00Z')),{start:'2026-10-30',end:'2026-11-05'});
 assert.deepEqual(statsRange('28',new Date('2026-11-06T03:00:00Z')),{start:'2026-10-09',end:'2026-11-05'});
 for(const days of ['0','365','-7','7 OR 1'])assert.throws(()=>statsRange(days));
});
test('CSV/TSV handles BOM, quoted comma, escaped quote, CRLF, embedded newlines',()=>{
 assert.deepEqual(parseDelimited('\uFEFFa,b\r\n"x,y","z""q"\r\n"two\nlines",v'),[{a:'x,y',b:'z"q'},{a:'two\nlines',b:'v'}]);
 assert.deepEqual(parseDelimited('a\tb\n1\t2','\t'),[{a:'1',b:'2'}]);assert.throws(()=>parseDelimited('a\n"broken'));
 assert.equal(reportText(Buffer.concat([Buffer.from([255,254]),Buffer.from('Date,Country\r\n2026-11-01,KR','utf16le')])),'Date,Country\r\n2026-11-01,KR');
});
test('Play never doubles overview totals with country rows or other apps/dates',()=>{
 const row={'Package Name':'com.koofylab.koofyreader',Date:'2026-11-01','Daily User Installs':'4','Daily User Uninstalls':'1'};
 const r=aggregatePlay([row,{...row,Country:'KR','Daily User Installs':'3'},{...row,Country:'JP','Daily User Installs':'1'},{...row,'Package Name':'other'},{...row,Date:'2026-10-01'}],'2026-11-01','2026-11-05');
 assert.equal(r.daily.length,1);assert.equal(r.daily[0].installs,4);assert.deepEqual(r.countries,[{country:'KR',installs:3},{country:'JP',installs:1}]);
});
test('Apple counts only this app and new units, excludes updates/redownload/IAP',()=>{
 const row={'Apple Identifier':'6814514729','Product Type Identifier':'1F','Country Code':'JP',Units:'3'};
 assert.deepEqual(aggregateApple([row,{...row,'Product Type Identifier':'7F'},{...row,'Product Type Identifier':'3F'},{...row,'Apple Identifier':'other'},{...row,'Product Type Identifier':'IA1'}],'2026-11-01'),[{date:'2026-11-01',country:'JP',downloads:3}]);
});
test('missing numeric cells are invalid reports, not zero installs',()=>{
 assert.throws(()=>aggregatePlay([{'Package Name':'com.koofylab.koofyreader',Date:'2026-11-01','Daily User Installs':''}],'2026-11-01','2026-11-05'));
 assert.throws(()=>aggregateApple([{'Apple Identifier':'6814514729','Product Type Identifier':'1F','Country Code':'KR',Units:''}],'2026-11-01'));
});
test('statistics rejects arbitrary sources and dimensions before external access',async()=>{
 const {readerStatistics}=await import('../src/reader-statistics');
 await assert.rejects(readerStatistics('https://example.com','7','all'));
 await assert.rejects(readerStatistics('analytics','7','arbitrary'));
 await assert.rejects(readerStatistics('analytics','999','all'));
});
