export async function buildRegisterPDF(title,lines,columns=[],rows=[],{logoBytes,closingLines=[]}={}){
 const [{jsPDF},{default:autoTable}]=await Promise.all([import('jspdf'),import('jspdf-autotable')]);
 const doc=new jsPDF();if(!logoBytes)throw Error('RBMI logo could not be loaded');
 const logo=new Uint8Array(logoBytes),image=doc.getImageProperties(logo),logoHeight=42*image.height/image.width;
 let y=43;doc.setFontSize(10);
 function write(line){const wrapped=doc.splitTextToSize(String(line),180);if(y+wrapped.length*5>275){doc.addPage();y=43;}doc.text(wrapped,14,y);y+=wrapped.length*5+3;}
 for(const line of lines)write(line);
 if(columns.length){autoTable(doc,{startY:y,head:[columns],body:rows,styles:{fontSize:9},margin:{top:43,bottom:20}});y=doc.lastAutoTable.finalY+10;}
 for(const line of closingLines)write(line);
 for(let page=1;page<=doc.getNumberOfPages();page++){doc.setPage(page);doc.addImage(logo,'PNG',14,8,42,logoHeight);doc.setFontSize(16);doc.text('RBMI Library',64,17);doc.setFontSize(12);doc.text(title,14,35);doc.setFontSize(9);doc.text('Page '+page+' of '+doc.getNumberOfPages(),195,288,{align:'right'});}
 return doc;
}
export async function registerPDF(title,lines,columns=[],rows=[],options={}){
 const response=await fetch((import.meta.env?.BASE_URL||'/')+'rbmi-logo.png');if(!response.ok)throw Error('RBMI logo could not be loaded');
 const doc=await buildRegisterPDF(title,lines,columns,rows,{...options,logoBytes:await response.arrayBuffer()});
 doc.save(title.replace(/[^a-z0-9-]/gi,'-')+'.pdf');
}
export const receiptNumber=r=>r.slip_no||'Slip number unavailable';
export function paymentReceipt(row,library){return registerPDF('Fine payment receipt',[
 'Library: '+library,'Slip number: '+receiptNumber(row),'Collection date: '+row.collected_on,
 'Borrower: '+row.patron_name+' ('+row.patron_code+')','Amount received: INR '+Number(row.amount).toFixed(2),
 'Payment method: '+row.payment_method,'Reference: '+row.reason,'Recorded by: '+(row.actor_name||'Name not recorded'),
 'This receipt confirms collection from the borrower. Institutional deposit is recorded separately.'
]);}
export function donationDocument(ack,library){
 const books=ack.books||[],quantity=books.reduce((n,b)=>n+Number(b.quantity),0),value=books.reduce((n,b)=>n+Number(b.value),0);
 return {title:'Donation acknowledgement',lines:[
 'Library: '+library,'Donor: '+ack.donor_name,...(ack.donor_contact?['Contact / address: '+ack.donor_contact]:[]),
 'Slip number: '+receiptNumber(ack),'Collection acknowledged through: '+ack.as_of,
 'Thank you, '+ack.donor_name+', for donating '+quantity+' book(s) to our library. Your support helps our students and faculty learn and discover.',
 'Total books received: '+quantity,'Estimated collection value: INR '+value.toFixed(2),
 'This single donor acknowledgement includes all received donations listed below.'
 ],columns:['Received','Institute','Book / author','Copies','Value (INR)','Recorded by'],rows:books.map(b=>[b.received_at,b.institute,b.title+' / '+b.author,b.quantity,Number(b.value).toFixed(2),b.recorded_by_name||'Name not recorded']),closingLines:[
 'With thanks, Librarian, '+library,'Signature / stamp: __________________',
 'Acknowledgement of books received; this is not a tax exemption certificate.'
 ]};
}
export function donationAcknowledgement(ack,library){const d=donationDocument(ack,library);return registerPDF(d.title,d.lines,d.columns,d.rows,{closingLines:d.closingLines});}

export function paymentsDocument(rows,library,slip){return {title:'Payments',lines:[
 'Library: '+library,'Slip number: '+receiptNumber(slip),'Prepared by: '+(slip.actor_name||'Name not recorded'),
 'Total payments: '+rows.length,'Total collected: INR '+rows.reduce((n,r)=>n+Number(r.amount),0).toFixed(2)
 ],columns:['Slip number','Borrower / code','Amount (INR)','Collected by','Reason / receipt','Collection date'],
 rows:rows.map(r=>[receiptNumber(r),r.patron_name+' / '+r.patron_code,Number(r.amount).toFixed(2),r.actor_name||'Name not recorded',r.reason,r.collected_on])};}
