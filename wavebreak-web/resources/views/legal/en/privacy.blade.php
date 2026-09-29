@extends('layout')
@section('title', 'Privacy Policy | WAVEBREAK')
@section('description', 'What data WAVEBREAK processes, why and for how long: an email address is all an account needs; traffic content and browsing history are not collected.')
@section('breadcrumb', 'Privacy Policy')
@section('body_class', 'wb-public page-legal')
@section('content')
<main id="main">
    <section class="download-hero site-hero site-hero--compact legal-hero" aria-labelledby="privacy-title">
        <div class="wb-container site-hero-inner">
            <div class="hero-copy">
                <p class="download-kicker"><span></span> Legal</p>
                <h1 id="privacy-title">Privacy<br><em>Policy.</em></h1>
                <p class="hero-description">In short: an email address is all an account needs. We don’t collect the content of your traffic or your browsing history, and we don’t sell data.</p>
            </div>
        </div>
    </section>
    <section class="site-section legal-section">
        <div class="wb-container legal-layout">
            <nav class="legal-toc" aria-label="Contents">
                <p class="section-number">CONTENTS</p>
                <ol>
                    <li><a href="#general">Who we are</a></li>
                    <li><a href="#collected">Data we process</a></li>
                    <li><a href="#not-collected">What we don’t collect</a></li>
                    <li><a href="#purposes">Purposes and legal bases</a></li>
                    <li><a href="#retention">Retention</a></li>
                    <li><a href="#recipients">Sharing and transfers</a></li>
                    <li><a href="#security">Security</a></li>
                    <li><a href="#rights">Your rights</a></li>
                    <li><a href="#us">US state privacy notice</a></li>
                    <li><a href="#cookies">Cookies</a></li>
                    <li><a href="#age">Children</a></li>
                    <li><a href="#changes">Changes</a></li>
                    <li><a href="#contacts">Contact</a></li>
                </ol>
            </nav>
            <article class="legal-body">
                <p class="legal-meta">Last updated: 29 September 2026</p>

                <section id="general">
                    <h2>1. Who we are</h2>
                    <p>1.1. WAVEBREAK is a secure network connection and access management platform for individuals, teams and businesses (the “Platform”). It consists of the website wavebreak.com.tr, the WAVEBREAK apps for desktop and mobile, and our server infrastructure.</p>
                    <p>1.2. The Platform is operated by the individual entrepreneur who owns WAVEBREAK (“we”, “us”). We are the controller of your personal data for the purposes of the EU General Data Protection Regulation (GDPR), the UK GDPR and similar laws.</p>
                    <p>1.3. Our guiding principle is data minimisation. We collect only what we need to create an account, provide access and apply the terms of your plan. We do not monitor what you do online.</p>
                    <p>1.4. This Policy applies to visitors of the English version of the website and to users of the Platform who chose English. It is available in Russian and Turkish as well; the Turkish version also serves as the information notice under Turkish Law No. 6698.</p>
                </section>

                <section id="collected">
                    <h2>2. Data we process</h2>
                    <h3>2.1. Account</h3>
                    <ul>
                        <li>your email address;</li>
                        <li>your password, stored only as an irreversible cryptographic hash (Argon2id) — we never know the password itself;</li>
                        <li>the dates you registered and last signed in, and your account status.</li>
                    </ul>
                    <h3>2.2. Telegram link</h3>
                    <p>Only if you link Telegram to your account yourself: your numeric Telegram ID, username and display name. You can unlink it in the app at any time.</p>
                    <h3>2.3. Devices</h3>
                    <ul>
                        <li>device name and platform (Windows, Android, iOS);</li>
                        <li>a device identifier assigned by the Platform to count devices against your plan’s limit;</li>
                        <li>the date of last activity.</li>
                    </ul>
                    <p>We do not collect hardware identifiers (IMEI, serial numbers, MAC addresses) or advertising identifiers. Unlocking the app with a fingerprint or face is handled by your operating system: biometric data never leaves your device and is never sent to us.</p>
                    <h3>2.4. Subscription and payments</h3>
                    <ul>
                        <li>your plan, its term and status;</li>
                        <li>for payments: amount, currency, status and the payment provider’s transaction ID.</li>
                    </ul>
                    <p>We do not receive or store your card details; the payment provider processes them.</p>
                    <h3>2.5. Traffic volume</h3>
                    <p>The total amount of data transferred, in bytes, per day — to apply your plan’s limits. Without content and without the addresses of the resources you visit.</p>
                    <h3>2.6. Support requests</h3>
                    <p>Your correspondence with support and anything you choose to tell us in it.</p>
                    <h3>2.7. Website</h3>
                    <p>The website uses only strictly necessary cookies (see section 10). There is no web analytics, no advertising pixels and no third-party trackers. You don’t need to register on the website.</p>
                </section>

                <section id="not-collected">
                    <h2>3. What we don’t collect</h2>
                    <p>3.1. We do not collect or store in the Platform’s databases:</p>
                    <ul>
                        <li>the content of your traffic;</li>
                        <li>the history of websites you visit, DNS queries or apps you use;</li>
                        <li>IP addresses linked to your account;</li>
                        <li>your location, contacts, files or other data from your device;</li>
                        <li>ID documents, phone number or date of birth;</li>
                        <li>data for targeted advertising.</li>
                    </ul>
                    <p>3.2. Your device’s IP address is technically necessary to establish a connection and is processed by our servers while the connection exists.</p>
                    <p>3.3. Our servers keep technical logs that may temporarily contain IP addresses and technical details of connections. These logs are used only to protect the Platform against attacks and to fix faults; they are not used to track users, are not shared with third parties and are accessible only to the Platform’s technical administrators.</p>
                </section>

                <section id="purposes">
                    <h2>4. Purposes and legal bases</h2>
                    <div class="legal-table" role="region" aria-label="Purposes of processing" tabindex="0">
                        <table>
                            <thead><tr><th>Purpose</th><th>Data</th><th>Legal basis (GDPR / UK GDPR)</th></tr></thead>
                            <tbody>
                                <tr><td>Registration, sign-in, account recovery</td><td>email, password hash</td><td>performance of a contract (Art. 6(1)(b))</td></tr>
                                <tr><td>Providing access and applying plan limits</td><td>devices, subscription, traffic volume</td><td>performance of a contract</td></tr>
                                <tr><td>Taking payments and bookkeeping</td><td>payment data</td><td>performance of a contract; legal obligation (Art. 6(1)(c))</td></tr>
                                <tr><td>Service notices: email confirmation, subscription expiry, changes to terms</td><td>email, Telegram (if linked)</td><td>performance of a contract</td></tr>
                                <tr><td>Answering your requests</td><td>correspondence</td><td>performance of a contract; legitimate interests (Art. 6(1)(f))</td></tr>
                                <tr><td>Protecting the Platform against abuse and attacks</td><td>technical logs</td><td>legitimate interests — keeping the service secure and available</td></tr>
                                <tr><td>News and offers — only if you ask for them</td><td>email</td><td>consent (Art. 6(1)(a)), which you can withdraw at any time</td></tr>
                            </tbody>
                        </table>
                    </div>
                    <p>We do not make decisions that produce legal or similarly significant effects for you based solely on automated processing.</p>
                </section>

                <section id="retention">
                    <h2>5. Retention</h2>
                    <p>5.1. Account, device and subscription data and traffic statistics are kept while your account exists.</p>
                    <p>5.2. After you delete your account, your data is deleted or anonymised within 30 days, except payment records, which we keep for the periods required by tax and accounting law.</p>
                    <p>5.3. Technical server logs are kept no longer than necessary to protect the Platform and fix faults.</p>
                    <p>5.4. Support correspondence is kept as long as needed to resolve your request and any related dispute.</p>
                </section>

                <section id="recipients">
                    <h2>6. Sharing and international transfers</h2>
                    <p>6.1. We do not sell your personal data and do not share it for advertising.</p>
                    <p>6.2. We share data only with parties the service cannot run without, and only as much as they need:</p>
                    <ul>
                        <li>hosting providers whose servers run the Platform’s infrastructure, including in the Russian Federation;</li>
                        <li>email services used to receive and answer your messages: Cloudflare, Inc. (USA), Google LLC (USA), Sendinblue SAS / Brevo (France) — your address and the content of the correspondence;</li>
                        <li>a payment provider — once payments are launched, only as needed to process a payment;</li>
                        <li>Telegram — only if you link your Telegram account or contact us there;</li>
                        <li>public authorities — only where and as required by law.</li>
                    </ul>
                    <p>6.3. Some recipients, and our own infrastructure, are located outside your country, including outside the European Economic Area and the United Kingdom. Where the law requires it, we rely on appropriate safeguards for such transfers, such as the European Commission’s Standard Contractual Clauses or the UK International Data Transfer Addendum.</p>
                </section>

                <section id="security">
                    <h2>7. Security</h2>
                    <ul>
                        <li>all connections to the Platform are encrypted;</li>
                        <li>passwords are stored only as Argon2id hashes;</li>
                        <li>the administration panel is not reachable from the internet: it can be accessed only over a private secure channel by a limited number of authorised people;</li>
                        <li>administrators’ actions are recorded in an audit log;</li>
                        <li>databases are not exposed to the public network and server access is restricted.</li>
                    </ul>
                </section>

                <section id="rights">
                    <h2>8. Your rights</h2>
                    <p>8.1. Depending on where you live, you have the right to: access your personal data and receive a copy; rectify inaccurate data; have your data erased; restrict processing; data portability; object to processing based on legitimate interests; withdraw consent at any time without affecting earlier processing; and lodge a complaint with a data protection supervisory authority — in the EU, the authority of your country of residence; in the UK, the Information Commissioner’s Office (ICO).</p>
                    <p>8.2. To exercise your rights, write to <a href="mailto:support@wavebreak.com.tr">support@wavebreak.com.tr</a> from the email address linked to your account. We will reply within one month; where the law allows, this can be extended by up to two further months for complex requests, in which case we will tell you why.</p>
                </section>

                <section id="us">
                    <h2>9. Notice for US residents</h2>
                    <p>9.1. In the last 12 months we have collected the following categories of personal information: identifiers (email address, device identifier assigned by us, Telegram ID if linked) and commercial information (plan and payment records). We collect them from you directly and use them for the purposes in section 4.</p>
                    <p>9.2. We do not sell personal information and do not share it for cross-context behavioural advertising, as those terms are defined in the California Consumer Privacy Act and similar state laws. We do not use sensitive personal information to infer characteristics about you.</p>
                    <p>9.3. You may request to know, access, correct or delete your personal information by emailing us as described in section 8. We will not discriminate against you for exercising these rights.</p>
                </section>

                <section id="cookies">
                    <h2>10. Cookies</h2>
                    <p>The website sets only strictly necessary cookies — a session cookie and a form-protection (CSRF) cookie. They are needed for the site to work and do not require consent. We do not use analytics, advertising or tracking cookies.</p>
                </section>

                <section id="age">
                    <h2>11. Children</h2>
                    <p>The Platform is intended for people aged 18 and over. We do not knowingly collect personal data from children. If you believe a child has given us personal data, contact us and we will delete it.</p>
                </section>

                <section id="changes">
                    <h2>12. Changes to this Policy</h2>
                    <p>The current version is always published on this page. We will notify you of material changes by email or in the app at least 10 days before they take effect.</p>
                </section>

                <section id="contacts">
                    <h2>13. Contact</h2>
                    <p>For any privacy question: <a href="mailto:support@wavebreak.com.tr">support@wavebreak.com.tr</a></p>
                    <p>The rules for using the Platform are in our <a href="/en/terms">Terms of Service</a>.</p>
                </section>
            </article>
        </div>
    </section>
</main>
@endsection
