@extends('layout')
@section('title', 'Gizlilik Politikası ve KVKK Aydınlatma Metni | WAVEBREAK')
@section('description', 'WAVEBREAK hangi kişisel verileri, hangi amaçla ve ne kadar süreyle işler: hesap için e-posta yeterlidir; trafik içeriği ve ziyaret geçmişi toplanmaz.')
@section('breadcrumb', 'Gizlilik ve KVKK Aydınlatma Metni')
@section('body_class', 'wb-public page-legal')
@section('content')
<main id="main">
    <section class="download-hero site-hero site-hero--compact legal-hero" aria-labelledby="privacy-title">
        <div class="wb-container site-hero-inner">
            <div class="hero-copy">
                <p class="download-kicker"><span></span> Belgeler</p>
                <h1 id="privacy-title">Gizlilik Politikası ve<br><em>KVKK Aydınlatma Metni.</em></h1>
                <p class="hero-description">Kısaca: hesap için e-posta adresi yeterlidir. Trafiğinizin içeriğini ve ziyaret ettiğiniz sitelerin geçmişini toplamayız, verilerinizi satmayız.</p>
            </div>
        </div>
    </section>
    <section class="site-section legal-section">
        <div class="wb-container legal-layout">
            <nav class="legal-toc" aria-label="İçindekiler">
                <p class="section-number">İÇİNDEKİLER</p>
                <ol>
                    <li><a href="#general">Veri sorumlusu</a></li>
                    <li><a href="#collected">İşlenen kişisel veriler</a></li>
                    <li><a href="#not-collected">İşlemediğimiz veriler</a></li>
                    <li><a href="#purposes">Amaçlar ve hukuki sebepler</a></li>
                    <li><a href="#method">Toplama yöntemi</a></li>
                    <li><a href="#retention">Saklama süreleri</a></li>
                    <li><a href="#recipients">Aktarım ve yurt dışı</a></li>
                    <li><a href="#security">Güvenlik</a></li>
                    <li><a href="#rights">KVKK md. 11 haklarınız</a></li>
                    <li><a href="#cookies">Çerezler</a></li>
                    <li><a href="#age">Yaş sınırı</a></li>
                    <li><a href="#changes">Değişiklikler</a></li>
                    <li><a href="#contacts">İletişim</a></li>
                </ol>
            </nav>
            <article class="legal-body">
                <p class="legal-meta">Son güncelleme: 29 Eylül 2026</p>

                <section id="general">
                    <h2>1. Veri sorumlusu</h2>
                    <p>1.1. Bu metin, 6698 sayılı Kişisel Verilerin Korunması Kanunu’nun (“KVKK”) 10. maddesi uyarınca aydınlatma yükümlülüğünün yerine getirilmesi ve gizlilik uygulamalarımızın açıklanması amacıyla hazırlanmıştır.</p>
                    <p>1.2. WAVEBREAK; bireysel kullanıcılar, ekipler ve işletmeler için güvenli ağ bağlantısı ve erişim yönetimi platformudur (“Platform”). Platform; wavebreak.com.tr internet sitesini, bilgisayar ve telefon için WAVEBREAK uygulamalarını ve sunucu altyapısını kapsar.</p>
                    <p>1.3. Veri sorumlusu, WAVEBREAK Platformu’nun sahibi olan gerçek kişi girişimcidir (“Veri Sorumlusu”, “biz”). İletişim: <a href="mailto:support@wavebreak.com.tr">support@wavebreak.com.tr</a>.</p>
                    <p>1.4. Temel ilkemiz veri minimizasyonudur: yalnızca hesap oluşturmak, erişim sağlamak ve plan koşullarını uygulamak için gereken verileri işleriz. İnternette ne yaptığınızı izlemeyiz.</p>
                </section>

                <section id="collected">
                    <h2>2. İşlenen kişisel veriler</h2>
                    <h3>2.1. Kimlik ve iletişim (hesap)</h3>
                    <ul>
                        <li>e-posta adresiniz;</li>
                        <li>şifreniz — yalnızca geri döndürülemez kriptografik özet (Argon2id) olarak saklanır, şifrenin kendisini bilmeyiz;</li>
                        <li>kayıt ve son giriş tarihleri, hesap durumu.</li>
                    </ul>
                    <h3>2.2. Telegram bağlantısı</h3>
                    <p>Yalnızca Telegram hesabınızı kendiniz bağlarsanız: Telegram kimlik numaranız, kullanıcı adınız ve görünen adınız. Bağlantıyı uygulamadan dilediğiniz zaman kaldırabilirsiniz.</p>
                    <h3>2.3. Cihaz bilgileri</h3>
                    <ul>
                        <li>cihaz adı ve platformu (Windows, Android, iOS);</li>
                        <li>cihaz limitinin uygulanması için Platform tarafından atanan cihaz tanımlayıcısı;</li>
                        <li>son etkinlik tarihi.</li>
                    </ul>
                    <p>Donanım tanımlayıcılarını (IMEI, seri numarası, MAC adresi) ve reklam kimliklerini toplamayız. Uygulamanın parmak izi veya yüz ile kilidinin açılması işletim sisteminiz tarafından yapılır; biyometrik veriler cihazınızdan çıkmaz ve bize iletilmez.</p>
                    <h3>2.4. Müşteri işlem bilgileri</h3>
                    <ul>
                        <li>planınız, abonelik süresi ve durumu;</li>
                        <li>ödemelerde: tutar, para birimi, durum ve ödeme kuruluşundaki işlem numarası.</li>
                    </ul>
                    <p>Kart bilgilerinizi almayız ve saklamayız; bunları ödeme kuruluşu işler.</p>
                    <h3>2.5. Trafik hacmi</h3>
                    <p>Plan limitlerinin uygulanması için günlük toplam aktarılan veri miktarı (bayt). İçerik ve ziyaret edilen adresler bu kapsamda yer almaz.</p>
                    <h3>2.6. Destek yazışmaları</h3>
                    <p>Destek ekibiyle yazışmalarınız ve bu yazışmalarda kendiniz paylaştığınız bilgiler.</p>
                </section>

                <section id="not-collected">
                    <h2>3. İşlemediğimiz veriler</h2>
                    <p>3.1. Platform veritabanlarında aşağıdakileri toplamaz ve saklamayız:</p>
                    <ul>
                        <li>trafiğinizin içeriği;</li>
                        <li>ziyaret ettiğiniz sitelerin, DNS sorgularının ve kullandığınız uygulamaların geçmişi;</li>
                        <li>hesabınızla ilişkilendirilmiş IP adresleri;</li>
                        <li>konum, rehber, dosyalar ve cihazınızdaki diğer veriler;</li>
                        <li>kimlik belgesi, telefon numarası, doğum tarihi;</li>
                        <li>hedefli reklam amaçlı veriler;</li>
                        <li>KVKK’nın 6. maddesinde sayılan özel nitelikli kişisel veriler.</li>
                    </ul>
                    <p>3.2. Cihazınızın IP adresi bağlantının kurulması için teknik olarak gereklidir ve bağlantı süresince sunucularımızca işlenir.</p>
                    <p>3.3. Sunucularımız, geçici olarak IP adreslerini ve bağlantılara ilişkin teknik bilgileri içerebilen teknik kayıtlar tutar. Bu kayıtlar yalnızca Platform’un saldırılara karşı korunması ve arızaların giderilmesi için kullanılır; kullanıcıların takibi için kullanılmaz, üçüncü kişilerle paylaşılmaz ve yalnızca Platform’un teknik yöneticileri tarafından erişilebilir.</p>
                </section>

                <section id="purposes">
                    <h2>4. İşleme amaçları ve hukuki sebepler</h2>
                    <div class="legal-table" role="region" aria-label="İşleme amaçları" tabindex="0">
                        <table>
                            <thead><tr><th>Amaç</th><th>Veriler</th><th>Hukuki sebep (KVKK md. 5/2)</th></tr></thead>
                            <tbody>
                                <tr><td>Kayıt, giriş, hesap kurtarma</td><td>e-posta, şifre özeti</td><td>sözleşmenin kurulması veya ifası (c)</td></tr>
                                <tr><td>Erişim sağlanması ve plan limitlerinin uygulanması</td><td>cihazlar, abonelik, trafik hacmi</td><td>sözleşmenin ifası (c)</td></tr>
                                <tr><td>Ödemelerin alınması ve muhasebe</td><td>ödeme bilgileri</td><td>sözleşmenin ifası (c); hukuki yükümlülük (ç)</td></tr>
                                <tr><td>Hizmet bildirimleri: e-posta doğrulama, abonelik süresi, koşul değişiklikleri</td><td>e-posta, Telegram (bağlıysa)</td><td>sözleşmenin ifası (c)</td></tr>
                                <tr><td>Taleplerinizin yanıtlanması</td><td>yazışmalar</td><td>sözleşmenin ifası (c); bir hakkın tesisi, kullanılması veya korunması (e)</td></tr>
                                <tr><td>Platform’un kötüye kullanıma ve saldırılara karşı korunması</td><td>teknik kayıtlar</td><td>meşru menfaat (f)</td></tr>
                                <tr><td>Haber ve kampanyalar — yalnızca isterseniz</td><td>e-posta</td><td>açık rıza (KVKK md. 5/1) ve 6563 sayılı Kanun kapsamında ticari elektronik ileti onayı</td></tr>
                            </tbody>
                        </table>
                    </div>
                    <p>Sizin için hukuki sonuç doğuran kararları yalnızca otomatik işleme dayanarak vermeyiz.</p>
                </section>

                <section id="method">
                    <h2>5. Toplama yöntemi</h2>
                    <p>Kişisel verileriniz; uygulamaya ve siteye girdiğiniz bilgiler, uygulamanın hizmet için gönderdiği teknik veriler ve e-posta yazışmaları aracılığıyla, elektronik ortamda ve otomatik yollarla toplanır.</p>
                </section>

                <section id="retention">
                    <h2>6. Saklama süreleri</h2>
                    <p>6.1. Hesap, cihaz ve abonelik verileri ile trafik istatistikleri hesabınız var olduğu sürece saklanır.</p>
                    <p>6.2. Hesabınızı sildiğinizde verileriniz 30 gün içinde silinir, yok edilir veya anonim hale getirilir. Ödeme kayıtları, vergi ve muhasebe mevzuatında öngörülen süreler boyunca saklanır.</p>
                    <p>6.3. Teknik sunucu kayıtları, Platform’un korunması ve arızaların giderilmesi için gerekli olan süreden daha uzun saklanmaz.</p>
                    <p>6.4. Destek yazışmaları, talebinizin ve olası uyuşmazlıkların çözümü için gerekli olduğu sürece saklanır.</p>
                </section>

                <section id="recipients">
                    <h2>7. Aktarım ve yurt dışına aktarım</h2>
                    <p>7.1. Kişisel verilerinizi satmayız ve reklam amacıyla paylaşmayız.</p>
                    <p>7.2. Veriler yalnızca hizmetin sunulması için zorunlu olan taraflara ve yalnızca gerekli olduğu ölçüde aktarılır:</p>
                    <ul>
                        <li>Platform altyapısının barındırıldığı hosting sağlayıcıları (Rusya Federasyonu dahil);</li>
                        <li>yazışmaların alınması ve yanıtlanması için kullanılan e-posta hizmetleri: Cloudflare, Inc. (ABD), Google LLC (ABD), Sendinblue SAS / Brevo (Fransa) — adresiniz ve yazışmanın içeriği;</li>
                        <li>ödeme kuruluşu — ödemeler başlatıldığında, yalnızca ödemenin gerçekleştirilmesi için gerekli ölçüde;</li>
                        <li>Telegram — yalnızca Telegram hesabınızı bağlarsanız veya bize Telegram üzerinden yazarsanız;</li>
                        <li>yetkili kamu kurum ve kuruluşları — yalnızca kanunen zorunlu hallerde.</li>
                    </ul>
                    <p>7.3. Platform altyapısı ve yukarıdaki alıcıların bir kısmı Türkiye dışında bulunduğundan kişisel verileriniz yurt dışına aktarılır. Bu aktarım, KVKK’nın 9. maddesinde öngörülen şartlara uygun olarak gerçekleştirilir.</p>
                </section>

                <section id="security">
                    <h2>8. Güvenlik</h2>
                    <ul>
                        <li>Platform ile tüm bağlantılar şifrelenir;</li>
                        <li>şifreler yalnızca Argon2id özeti olarak saklanır;</li>
                        <li>yönetim paneli internetten erişilemez; yalnızca sınırlı sayıda yetkili kişi tarafından kapalı ve güvenli bir kanal üzerinden erişilebilir;</li>
                        <li>yöneticilerin işlemleri denetim kaydına alınır;</li>
                        <li>veritabanları açık ağa kapalıdır, sunuculara erişim kısıtlıdır.</li>
                    </ul>
                </section>

                <section id="rights">
                    <h2>9. KVKK md. 11 kapsamındaki haklarınız</h2>
                    <p>9.1. Veri Sorumlusu’na başvurarak şu haklarınızı kullanabilirsiniz:</p>
                    <ul>
                        <li>kişisel verilerinizin işlenip işlenmediğini öğrenme;</li>
                        <li>işlenmişse buna ilişkin bilgi talep etme;</li>
                        <li>işlenme amacını ve bunların amacına uygun kullanılıp kullanılmadığını öğrenme;</li>
                        <li>yurt içinde veya yurt dışında aktarıldığı üçüncü kişileri bilme;</li>
                        <li>eksik veya yanlış işlenmişse düzeltilmesini isteme;</li>
                        <li>KVKK’nın 7. maddesindeki şartlar çerçevesinde silinmesini veya yok edilmesini isteme;</li>
                        <li>düzeltme, silme veya yok etme işlemlerinin verilerin aktarıldığı üçüncü kişilere bildirilmesini isteme;</li>
                        <li>münhasıran otomatik sistemlerle analiz edilmesi suretiyle aleyhinize bir sonucun ortaya çıkmasına itiraz etme;</li>
                        <li>kanuna aykırı işleme sebebiyle zarara uğramanız hâlinde zararın giderilmesini talep etme.</li>
                    </ul>
                    <p>9.2. Başvurunuzu, hesabınızda kayıtlı e-posta adresinden <a href="mailto:support@wavebreak.com.tr">support@wavebreak.com.tr</a> adresine gönderebilirsiniz. Başvurunuz, Veri Sorumlusuna Başvuru Usul ve Esasları Hakkında Tebliğ uyarınca en geç 30 gün içinde ve kural olarak ücretsiz sonuçlandırılır.</p>
                    <p>9.3. Başvurunuzun reddedilmesi, verilen cevabı yetersiz bulmanız veya süresinde cevap verilmemesi hâlinde Kişisel Verileri Koruma Kurulu’na şikâyette bulunabilirsiniz.</p>
                </section>

                <section id="cookies">
                    <h2>10. Çerezler</h2>
                    <p>Sitemiz yalnızca zorunlu çerezleri kullanır: oturum çerezi ve form güvenliği (CSRF) çerezi. Bunlar sitenin çalışması için gereklidir. Analiz, reklam veya takip çerezi kullanmayız.</p>
                </section>

                <section id="age">
                    <h2>11. Yaş sınırı</h2>
                    <p>Platform 18 yaşını doldurmuş kişilere yöneliktir. 18 yaşından küçükler Platform’u yalnızca veli veya vasilerinin izniyle kullanabilir.</p>
                </section>

                <section id="changes">
                    <h2>12. Değişiklikler</h2>
                    <p>Güncel metin her zaman bu sayfada yayımlanır. Önemli değişiklikleri, yürürlüğe girmelerinden en az 10 gün önce e-posta veya uygulama üzerinden bildiririz.</p>
                </section>

                <section id="contacts">
                    <h2>13. İletişim</h2>
                    <p>Kişisel verilerle ilgili tüm sorularınız için: <a href="mailto:support@wavebreak.com.tr">support@wavebreak.com.tr</a></p>
                    <p>Platform’un kullanım kuralları <a href="/tr/terms">Kullanım Koşulları</a>’nda yer alır.</p>
                </section>
            </article>
        </div>
    </section>
</main>
@endsection
