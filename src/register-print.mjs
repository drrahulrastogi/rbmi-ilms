export async function registerPDF(title,lines,columns=[],rows=[]){
 const [{jsPDF},{default:autoTable}]=await Promise.all([import('jspdf'),import('jspdf-autotable')]);
 const doc=new jsPDF();let y=20;doc.setFontSize(16);doc.text('RBMI Library',14,y);y+=10;doc.setFontSize(12);doc.text(title,14,y);y+=9;doc.setFontSize(10);
 for(const line of lines){const wrapped=doc.splitTextToSize(String(line),180);if(y+wrapped.length*5>275){doc.addPage();y=20;}doc.text(wrapped,14,y);y+=wrapped.length*5+3;}
 if(columns.length)autoTable(doc,{startY:y,head:[columns],body:rows,styles:{fontSize:9},margin:{bottom:20}});
 doc.save(title.replace(/[^a-z0-9-]/gi,'-')+'.pdf');
}
export const receiptNumber=r=>r.slip_no||'Slip number unavailable';
export function paymentReceipt(row,library){return registerPDF('Fine payment receipt',[
 'Library: '+library,'Slip number: '+receiptNumber(row),'Collection date: '+row.collected_on,
 'Borrower: '+row.patron_name+' ('+row.patron_code+')','Amount received: INR '+Number(row.amount).toFixed(2),
 'Payment method: '+row.payment_method,'Reference: '+row.reason,'Recorded by: '+(row.actor_name||'Name not recorded'),
 'This receipt confirms collection from the borrower. Institutional deposit is recorded separately.'
]);}
export function donationAcknowledgement(row,library){return registerPDF('Donation acknowledgement',[
 'Library: '+library+' / Institute: '+row.institute,'Slip number: '+receiptNumber(row),'Date received: '+row.received_at,
 'To: '+row.donor_name,...(row.donor_contact?[row.donor_contact]:[]),
 'Thank you for your generous donation of '+row.quantity+' book(s) to our library. Your support helps our students and faculty learn and discover.',
 'Title: '+row.title,'Estimated collection value: INR '+(row.quantity*row.unit_price).toFixed(2),
 'The books have been entered in our catalogue and are available through our normal library services.',
 'Recorded by: '+(row.recorded_by_name||'Name not recorded'),'With thanks,','Librarian, '+library,'Signature / stamp: __________________',
 'Acknowledgement of books received; this is not a tax exemption certificate.'
]);}
