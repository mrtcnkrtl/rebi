/**
 * Şirket künyesi: destek sayfası, yasal metinler ve alt bilgi aynı kaynaktan okur.
 * Boş bırakılan alan hiçbir sayfada gösterilmez; resmî kayıttaki değer gelince buraya yazılır.
 */
export const COMPANY = {
  legalName: "A3 Biyoteknoloji A.Ş.",
  brand: "Rebi",
  site: "https://rebiovil.com",
  email: "sosyal@rebiovil.com",
  /** Vergi levhasındaki adres. */
  address: "Hacıhalil Mah. 1207. Sk. No: 1 İç Kapı No: 5 Gebze / Kocaeli",
  mersis: "",
  taxOffice: "Uluçınar",
  taxNo: "0012270154",
  tradeRegistryNo: "",
  kep: "",
  phone: "",
  /** ETBİS'e kayıt yapıldıysa kayıt bilgisi (ör. doğrulama bağlantısı). */
  etbis: "",
};

/** Künye satırları: yalnız dolu alanlar. `en` İngilizce etiket döndürür. */
export function companyRows(en = false) {
  const c = COMPANY;
  const tax = [c.taxOffice, c.taxNo].filter(Boolean).join(" / ");
  return [
    [en ? "Trade name" : "Ticaret unvanı", c.legalName],
    [en ? "Address" : "Adres", c.address],
    [en ? "MERSIS no." : "MERSİS no", c.mersis],
    [en ? "Tax office / no." : "Vergi dairesi / no", tax],
    [en ? "Trade registry no." : "Ticaret sicil no", c.tradeRegistryNo],
    [en ? "Registered e-mail (KEP)" : "KEP adresi", c.kep],
    [en ? "E-mail" : "E-posta", c.email],
    [en ? "Phone" : "Telefon", c.phone],
    [en ? "Website" : "İnternet sitesi", c.site.replace("https://", "")],
    ["ETBİS", c.etbis],
  ].filter(([, value]) => Boolean(value));
}

/** Sözleşme metinlerinde satıcı / veri sorumlusu kimliği: tek satır. */
export function companyIdentity(en = false) {
  const c = COMPANY;
  const tax = [c.taxOffice, c.taxNo].filter(Boolean).join(" / ");
  return [
    c.legalName,
    c.address && `${en ? "Address" : "Adres"}: ${c.address}`,
    c.mersis && `MERSİS: ${c.mersis}`,
    tax && `${en ? "Tax office / no." : "Vergi dairesi / no"}: ${tax}`,
    `${en ? "E-mail" : "E-posta"}: ${c.email}`,
  ]
    .filter(Boolean)
    .join(" · ");
}
