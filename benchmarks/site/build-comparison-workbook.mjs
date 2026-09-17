import fs from 'node:fs/promises';
import path from 'node:path';
import { Workbook, SpreadsheetFile } from '@oai/artifact-tool';

const [inputFile,outputDir]=process.argv.slice(2);
const data=JSON.parse(await fs.readFile(inputFile,'utf8'));
const wb=Workbook.create();
const summary=wb.worksheets.add('Composite');
const scores=wb.worksheets.add('Scores');
const sites=wb.worksheets.add('Websites');
const short={A:'Sonnet original',B:'Sonnet direct revision',C:'Sonnet self-review',D:'Cross-model review',E:'Terra original',F:'Terra direct revision'};
const navy='#182638',blue='#2458A6',pale='#EEF3FA',gray='#5F6B78';
function style(sheet,range){sheet.showGridLines=false;const r=sheet.getRange(range);r.format.font={name:'Arial',size:11,color:navy};r.format.verticalAlignment='center';r.format.rowHeight=25;}
function header(sheet,range){const r=sheet.getRange(range);r.format.fill=navy;r.format.font={name:'Arial',size:11,bold:true,color:'#FFFFFF'};r.format.wrapText=true;r.format.horizontalAlignment='center';r.format.rowHeight=36;}
function width(sheet,col,px,last){sheet.getRange(`${col}1:${col}${last}`).format.columnWidthPx=px;}

style(scores,`A1:K${data.observations.length+1}`);
const raw=data.observations.map(o=>[o.protocol,o.benchmark,o.arm+' '+o.label,o.correct,o.planned,o.missing,null,null,null,o.url,o.eligible]);
scores.getRange('A1:K1').values=[['Protocol','Benchmark','Workflow','Correct','Planned','Missing','Delivered correct','Coverage','Upper bound','Source URL','Comparable input']];
scores.getRange(`A2:K${raw.length+1}`).values=raw;header(scores,'A1:K1');
const mapping=new Map();
for(let i=0;i<data.observations.length;i++){
  const o=data.observations[i],r=i+2;mapping.set(`${o.protocol}:${o.benchmark}:${o.arm}`,r);
  scores.getRange(`G${r}:I${r}`).formulas=[[`=IF(K${r},D${r}/E${r},"n.a.")`,`=IF(K${r},(E${r}-F${r})/E${r},"n.a.")`,`=IF(K${r},(D${r}+F${r})/E${r},"n.a.")`]];
}
scores.getRange(`D2:F${raw.length+1}`).setNumberFormat('0');scores.getRange(`G2:I${raw.length+1}`).setNumberFormat('0.0%');
for(const [c,w] of Object.entries({A:100,B:95,C:330,D:75,E:75,F:75,G:120,H:100,I:110,J:430,K:125}))width(scores,c,w,raw.length+1);
scores.getRange(`C2:C${raw.length+1}`).format.wrapText=true;scores.getRange(`A2:K${raw.length+1}`).format.rowHeight=42;scores.freezePanes.freezeRows(1);scores.freezePanes.freezeColumns(3);

style(summary,'A1:G36');summary.tabColor=navy;
summary.getRange('A2').values=[['Workflow composite scores']];summary.getRange('A2:G2').format.font={name:'Arial',size:16,bold:true,color:navy};summary.getRange('A2:G2').format.rowHeight=30;
summary.getRange('A3').values=[['Sources checked '+data.checked_on+' (UTC)']];
summary.getRange('B3:C3').values=[['BigCodeBench weight','LiveCodeBench weight']];summary.getRange('B3:C3').format.wrapText=true;summary.getRange('B3:C3').format.rowHeight=32;
summary.getRange('A4').values=[['Benchmark weights']];summary.getRange('B4').values=[[.5]];summary.getRange('C4').formulas=[['=IF(ISNUMBER(B4),1-B4,"n.a.")']];summary.getRange('B4:C4').setNumberFormat('0%');summary.getRange('B4').format.fill='#FFF3CF';summary.getRange('B4').format.font={name:'Arial',size:11,color:blue};
summary.getRange('A5').values=[['Change the yellow weight cell from 0% to 100%.']];summary.getRange('A5:G5').format.font={name:'Arial',size:11,italic:true,color:gray};
let row=7;const groupRows={};
for(const group of data.groups){
  summary.getRange(`A${row}`).values=[[group.title]];summary.getRange(`A${row}:G${row}`).format.font={name:'Arial',size:13,bold:true,color:navy};row++;
  summary.getRange(`A${row}:G${row}`).values=[['Workflow','BigCodeBench yield','LiveCodeBench yield','Composite /100','Coverage','Upper bound /100','Change vs B']];header(summary,`A${row}:G${row}`);row++;
  const begin=row;groupRows[group.id]=begin;const baseline=begin+group.rows.findIndex(r=>r.arm==='B');
  for(const item of group.rows){
    const b=mapping.get(`${group.id}:bcb:${item.arm}`),l=mapping.get(`${group.id}:lcb:${item.arm}`);
    summary.getRange(`A${row}`).values=[[item.arm+' '+short[item.arm]]];
    const guard=`AND(COUNT(B${row}:C${row})=2,ISNUMBER($B$4),$B$4>=0,$B$4<=1)`;
    summary.getRange(`B${row}:G${row}`).formulas=[[
      `='Scores'!G${b}`,`='Scores'!G${l}`,
      `=IF(${guard},100*SUMPRODUCT(B${row}:C${row},$B$4:$C$4),"n.a.")`,
      `=IF(${guard},'Scores'!H${b}*$B$4+'Scores'!H${l}*$C$4,"n.a.")`,
      `=IF(${guard},100*('Scores'!I${b}*$B$4+'Scores'!I${l}*$C$4),"n.a.")`,
      `=IF(COUNT(D${row},$D$${baseline})=2,D${row}-$D$${baseline},"n.a.")`
    ]];
    summary.getRange(`B${row}:C${row}`).setNumberFormat('0.0%');summary.getRange(`D${row}`).setNumberFormat('0.0');summary.getRange(`E${row}`).setNumberFormat('0.0%');summary.getRange(`F${row}`).setNumberFormat('0.0');summary.getRange(`G${row}`).setNumberFormat('+0.0;-0.0;0.0');
    summary.getRange(`B${row}:G${row}`).format.horizontalAlignment='right';
    if(item.arm==='B'||item.arm==='D')summary.getRange(`A${row}:G${row}`).format.fill=pale;
    row++;
  }
  row+=2;
}
const notes=[
  'Composite = weighted mean of correct / planned, scaled to 100. Default: equal benchmark weights.',
  'Coverage is the share of outcomes scored. Upper bounds assume all missing answers pass; they are not confidence intervals.',
  'Keep protocols separate: feedback uses held-out tests; the earlier tool-free studies used full test suites and different cohorts.',
  'External sites, calibration screens, rubric scores and archives are excluded. Cost is separate because some calls are unpriced.',
  'Feedback arms B/C/D/F receive visible diagnostics. Comparing a revision to its original also adds another model call.'
];
for(const note of notes){summary.getRange(`A${row}`).values=[[note]];summary.getRange(`A${row}:G${row}`).format.font={name:'Arial',size:11,color:gray};row++;}
for(const [c,w] of Object.entries({A:245,B:135,C:135,D:130,E:100,F:140,G:110}))width(summary,c,w,row);
summary.getRange(`A1:G${row}`).format.verticalAlignment='center';

const webRows=data.websites.map(w=>[w.title,w.type,w.metric,w.coverage,w.composite_group==='excluded'?'Excluded':w.composite_group,w.summary,w.url,w.source]);
style(sites,`A1:H${webRows.length+4}`);sites.getRange('A2').values=[['Website comparison and evidence sources']];sites.getRange('A2:H2').format.font={name:'Arial',size:16,bold:true,color:navy};sites.getRange('A4:H4').values=[['Website','Category','Scoring','Coverage / scope','Composite group','Result or use','Website URL','Evidence / methodology URL']];header(sites,'A4:H4');sites.getRange(`A5:H${webRows.length+4}`).values=webRows;
for(const [c,w] of Object.entries({A:310,B:145,C:245,D:280,E:120,F:410,G:440,H:470}))width(sites,c,w,webRows.length+4);
sites.getRange(`A5:H${webRows.length+4}`).format.wrapText=true;sites.getRange(`A5:H${webRows.length+4}`).format.rowHeight=52;sites.freezePanes.freezeRows(4);sites.freezePanes.freezeColumns(1);

await fs.mkdir(outputDir,{recursive:true});
wb.recalculate();
for(const group of data.groups){
  const begin=groupRows[group.id];const actual=summary.getRange(`D${begin}:D${begin+group.rows.length-1}`).values.flat();
  group.rows.forEach((r,i)=>{if(r.score!==null&&(typeof actual[i]!=='number'||!Number.isFinite(actual[i])||Math.abs(actual[i]-r.score)>1e-7))throw new Error('Composite mismatch '+group.id+':'+r.arm+' '+actual[i]);});
}
summary.getRange('B4').values=[[.75]];wb.recalculate();
const fixedRow=groupRows.fixed;const altered=summary.getRange(`D${fixedRow}`).values[0][0];
const fa=data.groups.find(g=>g.id==='fixed').rows.find(r=>r.arm==='A');
if(typeof altered!=='number'||!Number.isFinite(altered)||Math.abs(altered-(.75*fa.bcb+.25*fa.lcb))>1e-7)throw new Error('Weight sensitivity failed');
summary.getRange('B4').values=[[.5]];wb.recalculate();
const inspection=await wb.inspect({kind:'table',range:`Composite!A7:G${Math.min(row,26)}`,include:'values,formulas',tableMaxRows:22,tableMaxCols:7,maxChars:1800});
console.log(inspection.ndjson);
const errors=await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:30},summary:'formula error scan'});console.log(errors.ndjson);
const previews=process.argv.includes('--render-websites-only')?[['Websites','A2:F11','websites-preview.png']]:[['Composite','A1:G26','composite-preview.png'],['Scores','A1:I12','scores-preview.png'],['Websites','A2:F11','websites-preview.png']];
for(const [sheetName,range,file] of previews){
  const blob=await wb.render({sheetName,range,scale:1,format:'png'});await fs.writeFile(path.join(outputDir,file),new Uint8Array(await blob.arrayBuffer()));
}
await (await SpreadsheetFile.exportXlsx(wb)).save(path.join(outputDir,'benchmark-comparison.xlsx'));
console.log(JSON.stringify({output:path.join(outputDir,'benchmark-comparison.xlsx'),websites:webRows.length,observations:raw.length,weight_sensitivity:'passed'}));
