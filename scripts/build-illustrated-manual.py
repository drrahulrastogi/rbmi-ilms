"""Run from the repository root with Python, reportlab and Pillow installed."""
from pathlib import Path
import html,json,shutil,argparse
from PIL import Image as PILImage
from reportlab.platypus import BaseDocTemplate,PageTemplate,Frame,Paragraph,Spacer,PageBreak,NextPageTemplate,Image
from reportlab.platypus.tableofcontents import TableOfContents
from reportlab.lib.styles import getSampleStyleSheet,ParagraphStyle
from reportlab.lib.pagesizes import A4,landscape
from reportlab.lib import colors

r=Path.cwd();d=r/'docs/help';e=html.escape
chapters=json.loads((r/'docs/manual-content.json').read_text(encoding='utf-8'));screens=json.loads((r/'docs/manual-screenshots.json').read_text())
assert {c['slug'] for c in chapters}==set(screens)
for figures in screens.values():
 for fig in figures:
  p=d/'assets/screenshots'/fig['file'];assert p.exists(),p
  with PILImage.open(p) as im:assert im.width>=1000 and im.height>=600
css='body{font:16px/1.6 Arial,sans-serif;color:#18352b;max-width:1160px;margin:auto;padding:28px}h1{color:#123d2b}h2{color:#235f45}a{color:#185b8e}li{margin-bottom:12px}.logo{width:240px}nav{padding:20px;background:#eff5f1}.note{background:#f1f5f7;padding:16px}figure{margin:24px 0;break-inside:avoid}figure img{display:block;width:100%;height:auto;border:1px solid #d4dfd8}figcaption{padding:12px;background:#eff5f1;font-size:15px}.sample{font-size:13px;color:#53645c}footer{border-top:1px solid #ccc;margin-top:40px;font-size:12px}@media print{nav{display:none}body{padding:0}.chapter{break-before:page}figure{break-before:page}}'
(d/'assets/manual.css').write_text(css,encoding='utf-8')
def figures(c):
 return '<h2>Screen guide</h2><p class="sample">Captured from the application with sample records. Screen values are examples; your records and permissions may differ.</p>'+''.join('<figure><img src="assets/screenshots/'+f['file']+'" alt="'+e(f['caption'],quote=True)+'"><figcaption><strong>Screen '+str(n)+'.</strong> '+e(f['caption'])+'</figcaption></figure>' for n,f in enumerate(screens[c['slug']],1))
def body(c):return '<h1>'+e(c['title'])+'</h1><p>'+e(c['intro'])+'</p><h2>How to use this section</h2><ol>'+''.join('<li>'+e(x)+'</li>' for x in c['steps'])+'</ol><h2>Notes and limits</h2><div class="note">'+''.join('<p>'+e(x)+'</p>' for x in c['notes'])+'</div>'+figures(c)
def wrap(t,b):return '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>'+e(t)+'</title><link rel="stylesheet" href="assets/manual.css"></head><body><img class="logo" src="assets/rbmi-logo.png" alt="RBMI Group of Institutions"><p>RBMI ILMS 2.0 | Illustrated edition | 24 October 2026</p>'+b+'<footer>RBMI Library Network | Sample records in screenshots | No passwords shown</footer></body></html>'
nav='<nav><h1>Complete illustrated user manual</h1><p><a href="user-guide.pdf">Printable PDF</a> | <a href="printable.html">Printable HTML</a> | <a href="https://rbmi-ilms.vercel.app">Live application</a></p><ol>'+''.join('<li><a href="'+c['slug']+'.html">'+e(c['title'])+'</a></li>' for c in chapters)+'</ol></nav>'
(d/'index.html').write_text(wrap('RBMI Illustrated Manual',nav),encoding='utf-8')
for c in chapters:(d/(c['slug']+'.html')).write_text(wrap(c['title'],'<p><a href="index.html">Contents</a></p>'+body(c)),encoding='utf-8')
inline_nav=nav
for c in chapters:inline_nav=inline_nav.replace('href="'+c['slug']+'.html"','href="#'+c['slug']+'"')
for n in ['printable.html','user-guide.html']:(d/n).write_text(wrap('RBMI Complete Illustrated User Manual',inline_nav+''.join('<section class="chapter" id="'+c['slug']+'">'+body(c)+'</section>' for c in chapters)),encoding='utf-8')
files=['index.html','printable.html','user-guide.html']+[c['slug']+'.html' for c in chapters]+['assets/manual.css','assets/rbmi-logo.png']+['assets/screenshots/'+p for p in sorted({f['file'] for v in screens.values() for f in v})]
(d/'RBMI.hhp').write_text('[OPTIONS]\nCompatibility=1.1 or later\nCompiled file=RBMI.chm\nContents file=RBMI.hhc\nIndex file=RBMI.hhk\nDefault topic=index.html\nDisplay compile progress=Yes\nFull-text search=Yes\nLanguage=0x409 English (United States)\nTitle=RBMI Integrated Library Management System - Illustrated Manual\n\n[FILES]\n'+'\n'.join(files)+'\n')
sitemap='<HTML><HEAD><meta charset="utf-8"></HEAD><BODY><UL>'+''.join('<LI><OBJECT type="text/sitemap"><param name="Name" value="'+e(c['title'],quote=True)+'"><param name="Local" value="'+c['slug']+'.html"></OBJECT>' for c in chapters)+'</UL></BODY></HTML>'
for n in ['RBMI.hhc','RBMI.hhk']:(d/n).write_text(sitemap,encoding='utf-8')

styles=getSampleStyleSheet();styles.add(ParagraphStyle(name='BodyRBMI',fontName='Helvetica',fontSize=10,leading=14,textColor=colors.HexColor('#233a32'),spaceAfter=8));styles.add(ParagraphStyle(name='FigureTitle',fontName='Helvetica-Bold',fontSize=16,leading=20,textColor=colors.HexColor('#123d2b'),spaceAfter=7));styles.add(ParagraphStyle(name='CaptionRBMI',fontName='Helvetica',fontSize=10,leading=13,spaceAfter=9,textColor=colors.HexColor('#233a32')));styles['Heading1'].fontSize=23;styles['Heading1'].leading=28;styles['Heading1'].textColor=colors.HexColor('#123d2b');styles['Heading2'].fontSize=13;styles['Heading2'].leading=17
class IllustratedDoc(BaseDocTemplate):
 def afterFlowable(self,flowable):
  if isinstance(flowable,Paragraph) and flowable.style.name=='Heading1':
   text=flowable.getPlainText();key='chapter-'+text.split(' / ')[0];self.canv.bookmarkPage(key);self.canv.addOutlineEntry(text,key,0);self.notify('TOCEntry',(0,text,self.page,key))
def footer(cv,doc):
 width,height=cv._pagesize;cv.saveState();cv.setStrokeColor(colors.HexColor('#c8d8ce'));cv.line(36,32,width-36,32);cv.setFont('Helvetica',8);cv.setFillColor(colors.HexColor('#547064'));cv.drawString(36,19,'RBMI ILMS | Illustrated guide | 24 October 2026');cv.drawRightString(width-36,19,str(doc.page));cv.restoreState()
portrait=Frame(45,47,A4[0]-90,A4[1]-90,id='portrait',leftPadding=0,rightPadding=0,topPadding=0,bottomPadding=0)
lw,lh=landscape(A4);wide=Frame(36,44,lw-72,lh-80,id='wide',leftPadding=0,rightPadding=0,topPadding=0,bottomPadding=0)
doc=IllustratedDoc(str(d/'user-guide.pdf'),pagesize=A4,title='RBMI Complete Illustrated User Manual',author='RBMI Library Network')
doc.addPageTemplates([PageTemplate(id='Portrait',frames=[portrait],pagesize=A4,onPage=footer),PageTemplate(id='Landscape',frames=[wide],pagesize=landscape(A4),onPage=footer)])
toc=TableOfContents();toc.levelStyles=[ParagraphStyle(name='TOC',fontName='Helvetica',fontSize=9.5,leading=12,spaceBefore=1,textColor=colors.HexColor('#233a32'))]
story=[Image(str(d/'assets/rbmi-logo.png'),width=241,height=67),Spacer(1,38),Paragraph('Integrated Library<br/>Management System',styles['Title']),Spacer(1,18),Paragraph('Complete illustrated user manual',styles['FigureTitle']),Paragraph('24 October 2026 | 24 sections | Screenshots and operator instructions',styles['BodyRBMI']),Spacer(1,16),Paragraph('RBCET / RBMI Central Library<br/>RBCP Library<br/>RBCN Library<br/>RBGN Library',styles['Heading2']),Spacer(1,16),Paragraph('Live: https://rbmi-ilms.vercel.app<br/>Administrator: rahul.r@rbmi.in',styles['BodyRBMI']),Spacer(1,22),Paragraph('Screenshots use sample records and contain no real credentials. Screen pages use landscape orientation for legibility. Figures show controls; use the numbered instructions to complete each task.',styles['BodyRBMI']),PageBreak(),Paragraph('Contents',styles['FigureTitle']),toc]
for num,c in enumerate(chapters,1):
 story.extend([NextPageTemplate('Portrait'),PageBreak(),Paragraph(f'{num:02d} / '+e(c['title']),styles['Heading1']),Spacer(1,8),Paragraph(e(c['intro']),styles['BodyRBMI']),Paragraph('How to use this section',styles['Heading2'])])
 for k,t in enumerate(c['steps'],1):story.append(Paragraph(str(k)+'. '+e(t),styles['BodyRBMI']))
 story.append(Paragraph('Notes and limits',styles['Heading2']))
 for t in c['notes']:story.append(Paragraph(e(t),styles['BodyRBMI']))
 for n,fig in enumerate(screens[c['slug']],1):
  path=d/'assets/screenshots'/fig['file'];iw,ih=PILImage.open(path).size;scale=min((lw-72)/iw,432/ih)
  story.extend([NextPageTemplate('Landscape'),PageBreak(),Paragraph(f'{num:02d}.{n} / '+e(c['title']),styles['FigureTitle']),Paragraph(e(fig['caption'])+' <font color="#65766c">(Sample workspace)</font>',styles['CaptionRBMI']),Image(str(path),width=iw*scale,height=ih*scale)])
doc.multiBuild(story)
shutil.copy2(d/'user-guide.pdf',r/'docs/RBMI-Library-Manual.pdf')
parser=argparse.ArgumentParser();parser.add_argument('--output-dir',default='manual-output');args=parser.parse_args();out=Path(args.output_dir).resolve();out.mkdir(parents=True,exist_ok=True);shutil.copy2(d/'user-guide.pdf',out/'RBMI-Complete-User-Manual.pdf');shutil.copy2(d/'user-guide.html',out/'RBMI-Complete-User-Manual.html')
print('Built illustrated PDF, HTML and CHM source with',len(chapters),'sections and',sum(map(len,screens.values())),'screen references')
