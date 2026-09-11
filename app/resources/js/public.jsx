import React, { useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import '../css/app.css';

const rootEl = document.getElementById('public-react-root');

function routes() {
    return window.AURALITH_ROUTES || {};
}

function legal() {
    return window.AURALITH_LEGAL || {};
}

function csrf() {
    return document.querySelector('meta[name="csrf-token"]')?.content || '';
}

function asset(path) {
    return `/${String(path).replace(/^\/+/, '')}`;
}

function BrandMark({ logo = 'images/logo-mark.png?v=brand4', size = 52 }) {
    return (
        <span className="brand-mark" style={{ '--brand-mark-size': `${size}px` }} aria-hidden="true">
            <img src={asset(logo)} alt="" className="brand-logo" />
            <svg className="brand-mark__trace" viewBox="0 0 52 52" preserveAspectRatio="none">
                <rect className="brand-mark__border" x="1.5" y="1.5" width="49" height="49" rx="14" pathLength="100" />
                <rect className="brand-mark__runner" x="1.5" y="1.5" width="49" height="49" rx="14" pathLength="100" />
            </svg>
        </span>
    );
}

function MailIcon() {
    return (
        <svg viewBox="0 0 24 24" aria-hidden="true">
            <rect x="3" y="5" width="18" height="14" rx="3" />
            <path d="m5 8 7 5 7-5" />
        </svg>
    );
}

function TelegramIcon() {
    return (
        <svg viewBox="0 0 24 24" aria-hidden="true">
            <path d="M21 4 3.8 10.7c-1.2.5-1.2 1.2-.2 1.5l4.4 1.4 1.7 5.2c.2.7.4.9.9.9.4 0 .6-.2.9-.4l2.1-2 4.4 3.2c.8.4 1.4.2 1.6-.8L22.4 5c.3-1.2-.5-1.7-1.4-1Z" />
            <path d="m8.2 13.5 9.6-6.1" />
        </svg>
    );
}

function BroadcastIcon() {
    return (
        <svg viewBox="0 0 24 24" aria-hidden="true">
            <circle cx="12" cy="12" r="2" />
            <path d="M8.5 8.5a5 5 0 0 0 0 7M15.5 8.5a5 5 0 0 1 0 7M5.5 5.5a9 9 0 0 0 0 13M18.5 5.5a9 9 0 0 1 0 13" />
        </svg>
    );
}

function readProps() {
    if (!rootEl) return {};
    try {
        return JSON.parse(rootEl.dataset.props || '{}');
    } catch (e) {
        return {};
    }
}

function Header({ active = 'home', logo = 'images/logo-mark.png?v=brand4' }) {
    const r = routes();
    return (
        <header className="site-header">
            <div className="container nav">
                <a href={r.home} className="brand" aria-label="Auralith - главная страница">
                    <BrandMark logo={logo} />
                    <span>Auralith</span>
                </a>
                <nav className="nav-links" aria-label="Основная навигация">
                    <a href={`${r.home}#pricing`} className={active === 'pricing' ? 'active' : ''}>Тарифы</a>
                    <a href={`${r.home}#services`}>Услуги</a>
                    <a href={r.b2b} className={active === 'b2b' ? 'active' : ''}>B2B</a>
                    <a href={r.faq} className={active === 'faq' ? 'active' : ''}>FAQ</a>
                    <a href={`${r.home}#contact`}>Контакты</a>
                </nav>
                <a href={r.profile} className="profile-icon-btn" aria-label="Открыть профиль" title="Профиль">
                    <svg viewBox="0 0 24 24" aria-hidden="true">
                        <path d="M20 21a8 8 0 0 0-16 0" />
                        <circle cx="12" cy="7" r="4" />
                    </svg>
                </a>
            </div>
        </header>
    );
}

function Footer() {
    const r = routes();
    const details = legal();
    return (
        <footer className="site-footer-simple" id="site-footer">
            <div className="container footer-bottom">
                <div className="footer-layout">
                    <div className="footer-brand-block">
                        <a href={r.home} className="footer-logo">
                            <BrandMark size={52} />
                            <span>Auralith</span>
                        </a>
                        <p className="footer-tagline">
                            <span aria-hidden="true">«</span>
                            IT для всех
                            <span aria-hidden="true">»</span>
                        </p>
                        <p className="footer-about">Частные сетевые контуры и сопровождение IT-инфраструктуры.</p>
                    </div>
                    <div className="footer-columns">
                        <div className="footer-nav-block">
                            <p className="footer-nav-title">Навигация</p>
                            <a href={`${r.home}#pricing`} className="footer-nav-link">Тарифы</a>
                            <a href={`${r.home}#services`} className="footer-nav-link">Услуги</a>
                            <a href={r.b2b} className="footer-nav-link">B2B</a>
                            <a href={r.faq} className="footer-nav-link">FAQ</a>
                            <a href={`${r.home}#contact`} className="footer-nav-link">Контакты</a>
                            <a href={r.profile} className="footer-nav-link">Профиль</a>
                        </div>
                        <div className="footer-nav-block footer-contact-block">
                            <p className="footer-nav-title">Контакты</p>
                            <a href={`mailto:${details.email}`} className="footer-contact-link">
                                <MailIcon />
                                <span>{details.email}</span>
                            </a>
                            <a href="https://t.me/auralith_support" target="_blank" rel="noreferrer" className="footer-contact-link">
                                <TelegramIcon />
                                <span>Поддержка</span>
                            </a>
                            <a href="https://t.me/auralith_it" target="_blank" rel="noreferrer" className="footer-contact-link">
                                <BroadcastIcon />
                                <span>Канал</span>
                            </a>
                            <small className="footer-hours">{details.support_hours}</small>
                        </div>
                    </div>
                </div>
                <div className="footer-divider" />
                <div className="footer-bottom-row">
                    <p className="footer-copy">© {new Date().getFullYear()} Auralith. Все права защищены.</p>
                    <div className="footer-legal-links">
                        <a href={r.offer} className="footer-legal-link">Публичная оферта</a>
                        <a href={r.privacy} className="footer-legal-link">Политика конфиденциальности</a>
                        <a href={r.cookies} className="footer-legal-link">Cookie</a>
                        <a href={r.legal} className="footer-legal-link">Реквизиты</a>
                    </div>
                </div>
                <p className="footer-requisites">{details.operator_name} · ИНН: {details.inn} · ОГРНИП: {details.ogrnip} · Адрес для корреспонденции: {details.postal_address}</p>
            </div>
        </footer>
    );
}

const COOKIE_STORAGE_KEY = 'auralith_cookie_preferences';

function CookieBanner() {
    const r = routes();
    const [visible, setVisible] = useState(false);
    const [settingsOpen, setSettingsOpen] = useState(false);
    const [preferences, setPreferences] = useState({ functional: false, analytics: false });

    useEffect(() => {
        try {
            const saved = JSON.parse(localStorage.getItem(COOKIE_STORAGE_KEY) || 'null');
            if (saved) {
                setPreferences({
                    functional: Boolean(saved.functional),
                    analytics: Boolean(saved.analytics),
                });
                return;
            }
        } catch (e) {
            // Ignore a malformed local preference and ask the visitor again.
        }
        setVisible(true);
    }, []);

    const save = (next) => {
        const value = { necessary: true, ...next, updatedAt: new Date().toISOString() };
        localStorage.setItem(COOKIE_STORAGE_KEY, JSON.stringify(value));
        setPreferences(next);
        setVisible(false);
        setSettingsOpen(false);
        window.dispatchEvent(new CustomEvent('auralith:cookie-consent', { detail: value }));
    };

    if (!visible) {
        return null;
    }

    return (
        <aside className="cookie-banner" role="dialog" aria-modal="true" aria-label="Настройки cookie">
            <div className="cookie-banner__copy">
                <strong>Настройки cookie</strong>
                <p>Необходимые cookie обеспечивают вход, безопасность и сохранение выбора. Остальные категории включаются только после согласия. Подробнее в <a href={r.cookies}>cookie-политике</a>.</p>
                {settingsOpen && (
                    <div className="cookie-settings">
                        <label><input type="checkbox" checked disabled /> <span><b>Необходимые</b><small>Сессия, CSRF-защита и сохранение настроек. Всегда активны.</small></span></label>
                        <label><input type="checkbox" checked={preferences.functional} onChange={(e) => setPreferences({ ...preferences, functional: e.target.checked })} /> <span><b>Функциональные</b><small>Дополнительные настройки интерфейса и уведомлений.</small></span></label>
                        <label><input type="checkbox" checked={preferences.analytics} onChange={(e) => setPreferences({ ...preferences, analytics: e.target.checked })} /> <span><b>Аналитические</b><small>Обезличенная оценка работы страниц. Сейчас аналитика по умолчанию отключена.</small></span></label>
                    </div>
                )}
            </div>
            <div className="cookie-banner__actions">
                {settingsOpen && <button type="button" className="btn btn-secondary" onClick={() => save(preferences)}>Сохранить</button>}
                <button type="button" className="btn btn-secondary" onClick={() => save({ functional: false, analytics: false })}>Только необходимые</button>
                <button type="button" className="btn btn-secondary" onClick={() => setSettingsOpen(!settingsOpen)}>Настроить</button>
                <button type="button" className="btn btn-primary" onClick={() => save({ functional: true, analytics: true })}>Принять все</button>
            </div>
        </aside>
    );
}

function PageFrame({ active, children, className = '' }) {
    useEffect(() => {
        if (!window.location.hash) return;

        const targetId = decodeURIComponent(window.location.hash.slice(1));
        window.requestAnimationFrame(() => {
            document.getElementById(targetId)?.scrollIntoView();
        });
    }, []);

    return (
        <>
            <div className="auralith-bg" aria-hidden="true">
                <span className="auralith-bg__beam auralith-bg__beam--one" />
                <span className="auralith-bg__beam auralith-bg__beam--two" />
                <span className="auralith-bg__grid" />
            </div>
            <div className="page-glow page-glow-top" />
            <div className="page-glow page-glow-bottom" />
            <Header active={active} />
            <main className={className}>{children}</main>
            <Footer />
            <CookieBanner />
        </>
    );
}

function SparkField({ count = 16 }) {
    return (
        <div className="spark-field" aria-hidden="true">
            {Array.from({ length: count }).map((_, index) => <i key={index} style={{ '--i': index }} />)}
        </div>
    );
}

function ProductHeroScene() {
    const nodes = [
        'ams', 'fra', 'waw', 'hel', 'prg', 'sto', 'core', 'edge',
        'bot', 'pay', 'sub', 'api', 'tls', 'acl', 'ios', 'and',
        'win', 'qr', 'cp', 'tg', 'ha', 'log', 'dns', 'ops',
    ];

    return (
        <div className="hero-panel product-stage product-stage--react">
            <SparkField count={34} />
            <div className="hero-status-strip"><span>Private network</span><strong>core.auralith.ru</strong><em>online</em></div>
            <div className="react-orbit-scene react-product-map" aria-label="Экосистема Auralith">
                <div className="scene-mesh" aria-hidden="true">
                    {Array.from({ length: 5 }).map((_, index) => <span key={index} style={{ '--i': index }} />)}
                </div>
                <div className="node-field" aria-hidden="true">
                    {nodes.map((node, index) => <i key={node} title={node} style={{ '--i': index }} />)}
                </div>
                <div className="meteor-shower" aria-hidden="true">
                    {Array.from({ length: 6 }).map((_, index) => <i key={index} style={{ '--i': index }} />)}
                </div>
                <div className="signal-lanes" aria-hidden="true">
                    {Array.from({ length: 2 }).map((_, index) => <i key={index} style={{ '--i': index }} />)}
                </div>
                <div className="react-orbit-scene__aura" />
                <div className="react-orbit-ring react-orbit-ring--outer" />
                <div className="react-orbit-ring react-orbit-ring--middle" />
                <div className="react-orbit-ring react-orbit-ring--inner" />
                <div className="product-pill product-pill--access"><span>Access</span><small>client edge</small></div>
                <div className="product-pill product-pill--core"><span>Core</span><small>source of truth</small></div>
                <div className="product-pill product-pill--b2b"><span>B2B</span><small>ops layer</small></div>
                <div className="react-core">
                    <span className="react-core__pulse" />
                    <img src={asset('images/logo-mark.png?v=brand4')} alt="Auralith" />
                </div>
            </div>
            <div className="terminal terminal--alive">
                <pre><code>{`[auralith/infra]$ check-ha
 status: online
 access-policy: verified
 monitoring: enabled`}</code></pre>
            </div>
        </div>
    );
}

function B2BHeroScene() {
    return (
        <div className="hero-panel b2b-command-panel b2b-command-panel--react">
            <SparkField count={12} />
            <div className="b2b-radar b2b-radar--react">
                <span /><span /><span />
                <strong>Core</strong>
                <em>nodes / logs / diagnostics</em>
            </div>
            <div className="b2b-health-grid" aria-hidden="true">
                <div><span>HA</span><strong>planned</strong></div>
                <div><span>Backups</span><strong>verified</strong></div>
                <div><span>Alerts</span><strong>active</strong></div>
            </div>
            <div className="terminal terminal--alive"><pre><code>{`[auralith/b2b]$ audit stack
network: routes and firewall
data: backup restore test
app: observability
result: roadmap`}</code></pre></div>
        </div>
    );
}

function ContactSection({ title = 'Расскажите о задаче' }) {
    const r = routes();
    const [status, setStatus] = useState({ type: '', text: '' });
    const [sending, setSending] = useState(false);

    const submit = async (event) => {
        event.preventDefault();
        setSending(true);
        setStatus({ type: '', text: '' });

        const form = event.currentTarget;
        const response = await fetch(r.contact, {
            method: 'POST',
            headers: { Accept: 'application/json', 'X-CSRF-TOKEN': csrf() },
            body: new FormData(form),
            credentials: 'same-origin',
        }).catch(() => null);
        const data = response ? await response.json().catch(() => ({})) : {};

        if (response?.ok && data.ok) {
            form.reset();
            setStatus({ type: 'success', text: 'Запрос отправлен. Ответим на указанный email.' });
        } else {
            const validationText = data.errors ? Object.values(data.errors).flat().join(' ') : '';
            setStatus({ type: 'error', text: validationText || 'Не удалось отправить запрос. Попробуйте ещё раз.' });
        }
        setSending(false);
    };

    return (
        <section className="section contact-section" id="contact">
            <div className="container contact-grid">
                <div>
                    <p className="eyebrow">Контакты</p>
                    <h2>{title}</h2>
                    <p className="hero-text">Опишите частную инфраструктуру или IT-задачу. Ответим на email и предложим ближайший шаг.</p>
                </div>
                <form method="post" action={r.contact} className="contact-form" onSubmit={submit}>
                    <input type="hidden" name="_token" value={csrf()} />
                    <label>Имя<input name="name" required placeholder="Как к вам обращаться" /></label>
                    <label>Email<input type="email" name="email" required placeholder="name@company.ru" /></label>
                    <label>Задача<textarea name="message" required placeholder="Коротко о ситуации" /></label>
                    <label className="consent-check">
                        <input type="checkbox" name="privacy_consent" value="1" required />
                        <span>Я согласен на обработку персональных данных в соответствии с <a href={r.privacy} target="_blank" rel="noreferrer">Политикой обработки персональных данных</a>.</span>
                    </label>
                    <button className="btn btn-primary" type="submit" disabled={sending}>{sending ? 'Отправляем...' : 'Отправить'}</button>
                    {status.text && <p className={`form-status form-status--${status.type}`} role="status">{status.text}</p>}
                </form>
            </div>
        </section>
    );
}

function LandingPage({ plans = [] }) {
    const r = routes();
    const planCopy = (plan) => {
        const months = Number(plan.duration_months || 0);
        if (months >= 12) return 'Годовой доступ к частному сетевому контуру и инструментам управления подключёнными устройствами.';
        if (months >= 3) return 'Доступ к частной инфраструктуре на три месяца с управлением сроком и устройствами в кабинете.';
        return 'Доступ на месяц для подключения к собственной или разрешённой инфраструктуре.';
    };
    const normalizedPlans = plans.length ? plans : [
        { id: 1, name: '1 месяц', price_rub: 169, duration_months: 1, is_highlighted: false },
        { id: 2, name: '3 месяца', price_rub: 449, duration_months: 3, is_highlighted: true },
        { id: 3, name: '1 год', price_rub: 1490, duration_months: 12, is_highlighted: false },
    ];
    return (
        <PageFrame active="home">
            <section className="hero home-hero">
                <div className="container hero-grid">
                    <div className="hero-content">
                        <p className="eyebrow">Частный сетевой контур + B2B</p>
                        <h1>Управляемое подключение к вашей инфраструктуре</h1>
                        <p className="hero-text">Auralith помогает подключать сотрудников и устройства к собственным, корпоративным или иным разрешённым ресурсам, управлять доступом и сопровождать IT-инфраструктуру.</p>
                        <div className="hero-actions">
                            <a href="#pricing" className="btn btn-primary">Выбрать тариф</a>
                            <a href={r.b2b} className="btn btn-secondary">Решения для бизнеса</a>
                        </div>
                        <ul className="hero-metrics">
                            <li><strong>Private</strong><span>контур по правилам доступа</span></li>
                            <li><strong>Core</strong><span>статусы и устройства</span></li>
                            <li><strong>B2B</strong><span>управляемая инфраструктура</span></li>
                        </ul>
                    </div>
                    <ProductHeroScene />
                </div>
            </section>
            <section className="section" id="services">
                <div className="container">
                    <div className="section-head"><p className="eyebrow">Возможности</p><h2>Подключение к частным ресурсам и сопровождение инфраструктуры</h2></div>
                    <div className="cards cards-3">
                        <article className="card" style={{ '--card-i': 0 }}><h3>Частный сетевой контур</h3><p>Персональная конфигурация для подключения к ресурсам, которыми вы владеете или которыми вправе пользоваться.</p></article>
                        <article className="card" style={{ '--card-i': 1 }}><h3>Управление подключениями</h3><p>Статусы, устройства, версии клиентов и диагностика остаются в одном кабинете.</p></article>
                        <article className="card" style={{ '--card-i': 2 }}><h3>B2B-платформа</h3><p>Core-мониторинг, облако, корпоративные сети, DevOps, безопасность и внешний IT-отдел.</p></article>
                    </div>
                </div>
            </section>
            <section className="section section-dim" id="pricing">
                <div className="container">
                    <div className="section-head"><p className="eyebrow">Тарифы</p><h2>Выберите срок доступа к частному контуру</h2></div>
                    <div className="pricing-grid">
                        {normalizedPlans.map((plan, index) => (
                            <article className={`pricing-card ${plan.is_highlighted ? 'featured' : ''}`} key={plan.id || plan.name} style={{ '--card-i': index }}>
                                <span>{plan.duration_months || ''} мес.</span>
                                <h3>{plan.name}</h3>
                                <strong>{Number(plan.price_rub || plan.price || 0).toLocaleString('ru-RU')} ₽</strong>
                                <p>{planCopy(plan)}</p>
                                <a className={plan.is_highlighted ? 'btn btn-primary' : 'btn btn-secondary'} href={r.register}>Подключить</a>
                            </article>
                        ))}
                    </div>
                </div>
            </section>
            <section className="section command-section">
                <div className="container command-grid">
                    <div className="command-copy">
                        <p className="eyebrow">Единый контур</p>
                        <h2>Витрина, кабинет и Core работают как один продукт</h2>
                        <p>Пользователь видит понятный путь к разрешённым ресурсам, а внутри остаются статусы, устройства, платежи и обращения в поддержку.</p>
                    </div>
                    <div className="command-panel-mini">
                        <div className="command-route" aria-hidden="true">
                            <span className="command-route__line" />
                            <span className="command-route__pulse" />
                            <span className="command-node command-node--one">public</span>
                            <span className="command-node command-node--two">account</span>
                            <span className="command-node command-node--three">core</span>
                        </div>
                        <div className="command-panel-mini__copy">
                            <strong>public layer → account → core</strong>
                            <em>payments synced · devices visible · support faster</em>
                        </div>
                    </div>
                </div>
            </section>
            <section className="section flow-section">
                <div className="container flow-grid">
                    <div className="section-head section-head--left"><p className="eyebrow">Как это ощущается</p><h2>Меньше ручной рутины, больше предсказуемости</h2></div>
                    <div className="flow-steps">
                        <article><span>01</span><h3>Подключение</h3><p>Пользователь получает конфигурацию для частного контура, QR-код и понятный статус.</p></article>
                        <article><span>02</span><h3>Контроль</h3><p>Core держит подписки, устройства, версии клиентов и диагностику в одном контуре.</p></article>
                        <article><span>03</span><h3>Рост</h3><p>B2B-слой закрывает мониторинг, облако, сети, безопасность, DevOps и поддержку сотрудников.</p></article>
                    </div>
                </div>
            </section>
            <section className="section use-policy-section">
                <div className="container legal-notice">
                    <p className="eyebrow">Допустимое использование</p>
                    <h2>Сервис не предназначен для обхода ограничений доступа</h2>
                    <p>Auralith используется только для законного подключения к собственной, корпоративной или иной инфраструктуре, доступ к которой разрешён владельцем. Запрещены обход установленных ограничений, доступ к запрещённой информации и любые противоправные действия.</p>
                    <a href={r.offer} className="btn btn-secondary">Правила использования</a>
                </div>
            </section>
            <ContactSection />
        </PageFrame>
    );
}

function B2BPage() {
    const directions = [
        ['Cloud', 'Облачная инфраструктура, серверы, контейнеры и базы данных'],
        ['Network', 'Корпоративные сети, VPN, маршрутизация и сегментация'],
        ['Monitoring', 'Контроль состояния серверов, приложений и сервисов'],
        ['DevOps', 'CI/CD, Infrastructure as Code, Kubernetes и автоматизация'],
        ['Security', 'Аудит, firewall, контроль доступа и снижение рисков'],
        ['Support', 'Внешний IT-отдел для сотрудников, серверов и доступов'],
    ];
    const coreFeatures = [
        ['Infrastructure Monitoring', ['CPU и память', 'состояние дисков', 'сетевой трафик', 'доступность сервисов']],
        ['Application Monitoring', ['API', 'веб-приложения', 'микросервисы', 'фоновые задачи']],
        ['Alert Management', ['Telegram', 'Email', 'системы задач']],
        ['Analytics', ['отчёты по состоянию', 'проблемные зоны', 'рекомендации по оптимизации']],
    ];
    const capabilityGroups = [
        ['Auralith Cloud', 'Managed Cloud Infrastructure', ['VPS/VDS и виртуальные машины', 'Linux-серверы и Docker окружения', 'Kubernetes, Helm и автомасштабирование', 'PostgreSQL, MySQL, Redis, MongoDB', 'backup, recovery и контроль целостности']],
        ['Auralith Network', 'Corporate Network Engineering', ['LAN/WAN, VLAN и маршрутизация', 'Site-to-Site и Remote Access VPN', 'защищённые каналы', 'поддержка маршрутизаторов, коммутаторов и firewall', 'Wi-Fi инфраструктура и сегментация']],
        ['Network Security', 'Защита бизнес-инфраструктуры', ['аудит безопасности', 'контроль доступа', 'анализ открытых сервисов', 'снижение риска утечек и простоев']],
        ['Auralith DevOps', 'Accelerate Software Delivery', ['CI/CD для сборки, тестирования и доставки', 'Terraform и Ansible', 'автоматический запуск приложений и сервисов', 'контейнеризация и отказоустойчивость']],
        ['Auralith Support', 'Ваш внешний IT-отдел', ['поддержка сотрудников', 'серверы и сети', 'доступы и рабочие места', 'оборудование и регламенты']],
        ['Auralith Enterprise', 'Complete IT Operations', ['серверы, облака и сети', 'безопасность и контроль доступа', 'мониторинг, поддержка и обновления', 'развитие архитектуры и внедрение технологий']],
    ];
    const pricingGroups = [
        {
            title: 'Auralith Core',
            subtitle: 'Intelligent Infrastructure Monitoring',
            plans: [
                ['Core Starter', '4 900 ₽/мес', 'Для небольших проектов', ['до 10 устройств', 'базовый мониторинг', 'уведомления', 'отчёты']],
                ['Core Business', '14 900 ₽/мес', 'Для компаний', ['до 50 устройств', 'расширенный мониторинг', 'Grafana dashboards', 'контроль SLA']],
                ['Core Enterprise', 'от 39 900 ₽/мес', 'Для критичных систем', ['100+ устройств', '24/7 контроль', 'выделенный инженер', 'SLA']],
            ],
        },
        {
            title: 'Auralith Cloud',
            subtitle: 'Managed Cloud Infrastructure',
            plans: [
                ['Cloud Start', 'от 9 900 ₽/мес', 'Для стартапов', ['один или несколько серверов', 'настройка окружения', 'безопасность', 'мониторинг']],
                ['Cloud Business', 'от 29 900 ₽/мес', 'Для коммерческих сервисов', ['управление инфраструктурой', 'базы данных', 'резервирование', 'оптимизация']],
                ['Cloud Enterprise', 'от 79 900 ₽/мес', 'Для высоконагруженных систем', ['Kubernetes', 'High Availability', 'Disaster Recovery', 'архитектурное сопровождение']],
            ],
        },
        {
            title: 'Auralith Support',
            subtitle: 'Внешний IT-отдел',
            plans: [
                ['Basic', '490 ₽/польз./мес', 'Для небольших команд', ['консультации', 'удалённая помощь', 'настройка ПО']],
                ['Business', '1 490 ₽/польз./мес', 'Полное сопровождение', ['helpdesk', 'управление доступами', 'рабочие места']],
                ['Enterprise', '2 990 ₽/польз./мес', 'Для компаний', ['SLA', 'приоритетная поддержка', 'выделенный инженер']],
            ],
        },
    ];
    const sla = [
        ['Standard SLA', 'до 4 часов', 'обработка инцидента до 8 часов'],
        ['Business SLA', 'до 1 часа', 'обработка инцидента до 4 часов'],
        ['Enterprise SLA', 'до 15 минут', 'круглосуточное сопровождение'],
    ];
    const extraServices = [
        ['Аудит инфраструктуры', 'от 30 000 ₽'],
        ['Проектирование архитектуры', 'от 50 000 ₽'],
        ['Миграция серверов', 'от 25 000 ₽'],
        ['Настройка CI/CD', 'от 25 000 ₽'],
        ['Настройка Kubernetes', 'от 70 000 ₽'],
        ['Внедрение мониторинга', 'от 20 000 ₽'],
        ['Настройка VPN', 'от 10 000 ₽'],
    ];

    return (
        <PageFrame active="b2b">
            <section className="hero b2b-hero">
                <div className="container hero-grid">
                    <div className="hero-content">
                        <p className="eyebrow">Auralith B2B</p>
                        <h1>Управляемая IT-инфраструктура для современного бизнеса</h1>
                        <p className="hero-text">Полный цикл управления инфраструктурой: от проектирования архитектуры до ежедневной эксплуатации. Мы закрываем техническую сложность, чтобы команда могла сосредоточиться на бизнесе.</p>
                        <div className="hero-actions"><a href="#contact" className="btn btn-primary">Обсудить инфраструктуру</a><a href="#b2b-pricing" className="btn btn-secondary">Пакеты и SLA</a></div>
                        <ul className="hero-metrics">
                            <li><strong>24/7</strong><span>мониторинг и алерты</span></li>
                            <li><strong>SLA</strong><span>прозрачная реакция</span></li>
                            <li><strong>Core</strong><span>серверы, приложения, сеть</span></li>
                        </ul>
                    </div>
                    <B2BHeroScene />
                </div>
            </section>

            <section className="section b2b-capabilities">
                <div className="container">
                    <div className="b2b-section-layout">
                        <div className="section-head section-head--left">
                            <p className="eyebrow">Почему Auralith</p>
                            <h2>Infrastructure Without Complexity</h2>
                        </div>
                        <div className="b2b-lead-copy">
                            <p>Сайты должны работать 24/7, сотрудники должны иметь стабильный доступ к системам, данные должны быть защищены, а инфраструктура должна масштабироваться без хаоса.</p>
                            <p>Auralith превращает сложную инфраструктуру в управляемый сервис: понятная зона ответственности, наблюдаемость, регламенты реакции и инженерное сопровождение.</p>
                        </div>
                    </div>
                    <div className="b2b-direction-list">
                        {directions.map(([title, text]) => (
                            <div className="b2b-direction-row" key={title}>
                                <strong>{title}</strong>
                                <span>{text}</span>
                            </div>
                        ))}
                    </div>
                </div>
            </section>

            <section className="section section-dim">
                <div className="container">
                    <div className="b2b-section-layout">
                        <div className="section-head section-head--left">
                            <p className="eyebrow">Auralith Core</p>
                            <h2>Intelligent Infrastructure Monitoring</h2>
                        </div>
                        <div className="b2b-lead-copy">
                            <p>Контроль инфраструктуры в режиме реального времени: серверы, базы данных, приложения, сетевое оборудование, виртуальные машины и облачные ресурсы.</p>
                        </div>
                    </div>
                    <div className="b2b-compact-grid">
                        {coreFeatures.map(([title, items]) => (
                            <article className="b2b-compact-card" key={title}>
                                <h3>{title}</h3>
                                <ul>{items.map((item) => <li key={item}>{item}</li>)}</ul>
                            </article>
                        ))}
                    </div>
                </div>
            </section>

            <section className="section b2b-capabilities">
                <div className="container">
                    <div className="b2b-section-layout">
                        <div className="section-head section-head--left">
                            <p className="eyebrow">Направления</p>
                            <h2>Cloud, Network, Security, DevOps и внешний IT-отдел</h2>
                        </div>
                        <div className="b2b-lead-copy">
                            <p>Направления можно подключать отдельно или объединять в единый контур эксплуатации: от серверной среды до рабочих мест и регламентов поддержки.</p>
                        </div>
                    </div>
                    <div className="b2b-service-matrix">
                        {capabilityGroups.map(([title, subtitle, items]) => (
                            <div className="b2b-service-row" key={title}>
                                <div>
                                    <strong>{title}</strong>
                                    <span>{subtitle}</span>
                                </div>
                                <p>{items.join(' · ')}</p>
                            </div>
                        ))}
                    </div>
                </div>
            </section>

            <section className="section b2b-pricing-section" id="b2b-pricing">
                <div className="container">
                    <div className="b2b-section-layout">
                        <div className="section-head section-head--left b2b-pricing-head">
                            <p className="eyebrow">Пакеты</p>
                            <h2>Тарифы для мониторинга, облака и поддержки</h2>
                        </div>
                        <div className="b2b-lead-copy">
                            <p>Можно начать с отдельного направления или собрать комплексное сопровождение под вашу нагрузку.</p>
                        </div>
                    </div>
                    {pricingGroups.map((group) => (
                        <div className="b2b-package-block" key={group.title}>
                            <div className="b2b-package-head">
                                <span>{group.title}</span>
                                <strong>{group.subtitle}</strong>
                            </div>
                            <div className="b2b-rate-table">
                                <div className="b2b-rate-row b2b-rate-row--head">
                                    <span>Пакет</span>
                                    <span>Стоимость</span>
                                    <span>Назначение</span>
                                    <span>Состав</span>
                                </div>
                                {group.plans.map((item, idx) => (
                                    <div className={`b2b-rate-row ${idx === 2 ? 'is-featured' : ''}`} key={item[0]}>
                                        <strong>{item[0]}</strong>
                                        <span>{item[1]}</span>
                                        <span>{item[2]}</span>
                                        <p>{item[3].join(' · ')}</p>
                                    </div>
                                ))}
                            </div>
                        </div>
                    ))}
                    <div className="b2b-pricing-cta">
                        <a href="#contact" className="btn btn-primary">Обсудить инфраструктуру</a>
                    </div>
                </div>
            </section>

            <section className="section section-dim b2b-process-section">
                <div className="container b2b-process">
                    <div className="b2b-section-layout">
                        <div className="section-head section-head--left">
                            <p className="eyebrow">SLA</p>
                            <h2>Прозрачность реакции и сопровождения</h2>
                        </div>
                        <div className="b2b-lead-copy">
                            <p>Уровень реакции фиксируется под критичность систем. SLA согласуется в договоре и привязан к реальным каналам поддержки.</p>
                        </div>
                    </div>
                    <div className="b2b-sla-grid">
                        {sla.map(([title, response, detail]) => (
                            <div className="b2b-sla-item" key={title}>
                                <span>{title}</span>
                                <strong>{response}</strong>
                                <p>{detail}</p>
                            </div>
                        ))}
                    </div>
                </div>
            </section>

            <section className="section b2b-seo">
                <div className="container seo-copy">
                    <div className="b2b-section-layout">
                        <div className="section-head section-head--left">
                            <p className="eyebrow">Дополнительные услуги</p>
                            <h2>Точечные работы для инфраструктуры</h2>
                        </div>
                        <div className="b2b-lead-copy">
                            <p>Разовые работы можно оформить отдельно: аудит, миграция, внедрение мониторинга, настройка VPN или автоматизация поставки.</p>
                        </div>
                    </div>
                    <div className="b2b-extra-table">
                        {extraServices.map(([title, price]) => (
                            <div className="b2b-extra-row" key={title}>
                                <span>{title}</span>
                                <strong>{price}</strong>
                            </div>
                        ))}
                    </div>
                </div>
            </section>

            <ContactSection title="Расскажите, что должно работать стабильнее" />
        </PageFrame>
    );
}

const faqItems = [
    ['Для чего предназначен Auralith?', 'Для подключения пользователей и устройств к собственной, корпоративной или иной частной инфраструктуре, доступ к которой разрешён владельцем.'],
    ['Можно ли использовать сервис для обхода блокировок?', 'Нет. Сервис не предназначен для обхода ограничений доступа, получения запрещённой информации или иных противоправных действий. Такое использование запрещено офертой.'],
    ['Как быстро активируется подписка после оплаты?', 'Обычно доступ активируется автоматически после подтверждения платежа. Фактический срок зависит от платёжного провайдера и состояния инфраструктуры.'],
    ['На каких устройствах работает сервис?', 'Поддерживаются Windows, macOS, Linux, iOS и Android при наличии совместимого приложения и разрешённой конфигурации.'],
    ['Есть ли гарантии скорости и задержки?', 'Нет фиксированной гарантии для публичных тарифов. Показатели зависят от сети пользователя, провайдера, региона, маршрута, устройства и текущей нагрузки. Отдельный SLA возможен только по письменному B2B-договору.'],
    ['Есть ли ограничения по объёму данных?', 'В тарифах может не применяться отдельная квота объёма, однако действуют технические ограничения, правила добросовестного использования и меры защиты общей инфраструктуры.'],
    ['Как подключиться к сервису?', 'Зарегистрируйтесь, выберите тариф и получите в личном кабинете конфигурацию для подключения к вашим разрешённым ресурсам.'],
    ['Можно ли использовать сервис на нескольких устройствах?', 'Количество устройств и одновременных подключений определяется выбранным тарифом и отображается в личном кабинете.'],
    ['Какие способы оплаты доступны?', 'Доступные способы показываются перед оплатой. Платёж обрабатывает внешний платёжный провайдер.'],
    ['Есть ли автопродление и как его отменить?', 'Если при оплате подключено рекуррентное списание, это указывается в интерфейсе. Автопродление можно отключить в личном кабинете; доступ сохранится до конца оплаченного периода.'],
    ['Как отказаться от услуги и запросить возврат?', 'Направьте заявление на email для претензий. Возврат рассчитывается с учётом фактически оказанной части услуги, понесённых расходов и обязательных требований закона. При технической невозможности подключения укажите дату оплаты и описание ошибки.'],
    ['Что происходит после окончания подписки?', 'Доступ к частному контуру приостанавливается. Продление выполняется пользователем в личном кабинете; если автопродление отключено, новых списаний не будет.'],
    ['Как получить помощь?', 'Напишите на auralith_ru@outlook.com. Telegram @auralith_support доступен как дополнительный оперативный канал.'],
];

function FAQPage() {
    const [open, setOpen] = useState(0);
    return (
        <PageFrame active="faq">
            <section className="faq-page-section">
                <div className="container">
                    <p className="section-eyebrow">Поддержка</p>
                    <h1 className="section-title">Часто задаваемые вопросы</h1>
                    <p style={{ color: 'var(--muted)', textAlign: 'center', marginBottom: 48, fontSize: '.95rem' }}>Не нашли ответ? Напишите на <a href="mailto:auralith_ru@outlook.com" style={{ color: 'var(--accent)' }}>auralith_ru@outlook.com</a>. Telegram остаётся дополнительным каналом.</p>
                    <div className="faq-list">
                        {faqItems.map(([q, a], idx) => (
                            <div className={`faq-item ${open === idx ? 'open' : ''}`} key={q}>
                                <button className="faq-q" type="button" onClick={() => setOpen(open === idx ? -1 : idx)}>{q}<span className="faq-icon">{open === idx ? '×' : '+'}</span></button>
                                <div className="faq-a"><p>{a}</p></div>
                            </div>
                        ))}
                    </div>
                </div>
            </section>
        </PageFrame>
    );
}

function LegalRequisites() {
    const details = legal();
    return (
        <div className="legal-requisites">
            <p><strong>{details.operator_name}</strong></p>
            <p><span>ИНН:</span> {details.inn}</p>
            <p><span>ОГРНИП:</span> {details.ogrnip}</p>
            <p><span>Дата регистрации:</span> {details.registration_date}</p>
            <p><span>Регистрирующий орган:</span> {details.registrar}</p>
            <p><span>Место регистрации:</span> {details.registration_place}</p>
            <p><span>Адрес для корреспонденции:</span> {details.postal_address}</p>
            <p><span>Email и претензии:</span> <a href={`mailto:${details.email}`}>{details.email}</a></p>
            <p><span>Режим поддержки:</span> {details.support_hours}</p>
        </div>
    );
}

function OfferDocument() {
    const details = legal();
    return (
        <>
            <h2>1. Общие положения</h2>
            <p>Настоящий документ является публичной офертой Исполнителя заключить договор оказания информационно-технологических услуг Auralith. Редакция действует с 8 июня 2026 года.</p>
            <p>Акцептом оферты считается совокупность действий: регистрация, подтверждение согласия с документами и оплата выбранной услуги. До оплаты Пользователь обязан ознакомиться с тарифом, сроком, автопродлением и ограничениями.</p>

            <h2>2. Исполнитель</h2>
            <LegalRequisites />

            <h2>3. Предмет и назначение сервиса</h2>
            <p>Исполнитель предоставляет на срок тарифа доступ к программному комплексу для организации управляемого подключения к собственной, корпоративной или иной частной инфраструктуре, доступ к которой Пользователю разрешён владельцем, а также к функциям кабинета, управления устройствами и технической поддержки.</p>
            <p><strong>Сервис не предназначен для обхода ограничений доступа к информации, доступа к запрещённым ресурсам или совершения иных противоправных действий.</strong> Исполнитель не обещает доступность любых сайтов, платформ или внешних ресурсов.</p>

            <h2>4. Порядок оказания услуг</h2>
            <ul>
                <li>Доступ активируется после подтверждения оплаты платёжным провайдером.</li>
                <li>Срок услуги указывается в тарифе и личном кабинете.</li>
                <li>Пользователь самостоятельно обеспечивает совместимое устройство, приложение и интернет-соединение.</li>
                <li>Плановые работы, аварии, действия операторов связи и внешних поставщиков могут временно влиять на работу.</li>
            </ul>

            <h2>5. Показатели качества и технические ограничения</h2>
            <p>Публичные тарифы не включают гарантированный SLA, фиксированную задержку или безусловную доступность 99,9%. Скорость, задержка и доступность зависят от сети Пользователя, провайдера, маршрута, региона, устройства, нагрузки и внешних сервисов. Отдельный SLA действует только при его письменном согласовании в B2B-договоре.</p>
            <p>Если тариф не содержит отдельной квоты трафика, это не отменяет технических ограничений, правил добросовестного использования и мер защиты общей инфраструктуры.</p>

            <h2>6. Стоимость, оплата и автопродление</h2>
            <ul>
                <li>Цена, срок и состав тарифа показываются до оплаты.</li>
                <li>Оплата проводится внешним платёжным провайдером. Исполнитель не получает полный номер банковской карты.</li>
                <li>Рекуррентные списания применяются только при отдельном подключении автопродления в платёжном интерфейсе.</li>
                <li>Автопродление можно отключить в личном кабинете. Отключение прекращает будущие списания и не сокращает уже оплаченный срок.</li>
            </ul>

            <h2>7. Отказ от услуги и возврат</h2>
            <p>Пользователь вправе отказаться от договора, направив заявление на <a href={`mailto:${details.email}`}>{details.email}</a>. В заявлении указываются аккаунт, дата и сумма оплаты, причина обращения и способ обратной связи.</p>
            <p>Возврат определяется с учётом фактически оказанной части услуги, документально подтверждённых расходов Исполнителя и обязательных требований законодательства. При подтверждённой технической невозможности начать использование по причинам на стороне Исполнителя вопрос о возврате рассматривается индивидуально. Срок возврата зависит от платёжного провайдера и банка.</p>

            <h2>8. Обязанности и запреты</h2>
            <p>Пользователь обязан хранить данные доступа в тайне, применять сервис только к разрешённым ресурсам и соблюдать законодательство. Запрещены обход блокировок и иных ограничений доступа, распространение запрещённой информации, атаки, сканирование без разрешения, спам, нарушение прав третьих лиц и создание чрезмерной нагрузки.</p>
            <p>При признаках нарушения Исполнитель вправе временно ограничить доступ для проверки, уведомить Пользователя и расторгнуть договор при существенном или повторном нарушении.</p>

            <h2>9. Ответственность</h2>
            <p>Стороны отвечают в пределах закона. Исполнитель не отвечает за оборудование и сеть Пользователя, действия операторов связи, платёжных систем и иных независимых третьих лиц, а также за недоступность ресурса, к которому у Пользователя отсутствует законное право доступа.</p>

            <h2>10. Претензии и споры</h2>
            <p>Претензия направляется на <a href={`mailto:${details.email}`}>{details.email}</a> или по адресу для корреспонденции, указанному в реквизитах. Электронное обращение должно содержать ФИО или идентификатор Пользователя, описание требования, дату оплаты и подтверждающие материалы. Ответ направляется по указанному адресу в срок, установленный законом.</p>

            <h2>11. Персональные данные</h2>
            <p>Обработка персональных данных выполняется по <a href={routes().privacy}>Политике обработки персональных данных</a>. Согласие на рекламные сообщения, если они появятся, запрашивается отдельно и не является условием покупки.</p>

            <h2>12. Изменение оферты</h2>
            <p>Новая редакция публикуется на сайте с датой вступления в силу. Изменения не лишают Пользователя прав, предоставленных императивными нормами законодательства.</p>
        </>
    );
}

function PrivacyDocument() {
    const details = legal();
    return (
        <>
            <h2>1. Общие положения</h2>
            <p>Политика действует с 8 июня 2026 года и определяет порядок обработки персональных данных на сайте, в личном кабинете, формах поддержки и связанных сервисах Auralith.</p>

            <h2>2. Оператор</h2>
            <LegalRequisites />

            <h2>3. Какие данные обрабатываются</h2>
            <ul>
                <li>Имя, логин, email и сведения, указанные в обращении.</li>
                <li>Telegram ID и имя пользователя, если Пользователь самостоятельно связывает Telegram с аккаунтом.</li>
                <li>Сведения об аккаунте, тарифе, оплате, устройствах и событиях поддержки.</li>
                <li>IP-адрес, дата и время запроса, браузер, операционная система, технические журналы и идентификаторы сессии.</li>
                <li>Cookie и локальные настройки в объёме, описанном в <a href={routes().cookies}>cookie-политике</a>.</li>
            </ul>
            <p>Исполнитель не получает полный номер банковской карты: платёжные данные обрабатывает платёжный провайдер.</p>

            <h2>4. Цели и основания обработки</h2>
            <ul>
                <li>Регистрация, аутентификация и исполнение договора.</li>
                <li>Активация тарифа, учёт платежей и предотвращение злоупотреблений.</li>
                <li>Ответ на обращения, диагностика и техническая поддержка.</li>
                <li>Обеспечение безопасности, сохранение журналов событий и выполнение требований закона.</li>
                <li>Улучшение интерфейса на основании согласия, когда оно требуется.</li>
            </ul>
            <p>Основания: согласие субъекта, заключение и исполнение договора, законные обязанности Оператора и защита прав сторон. Рекламные рассылки без отдельного согласия не выполняются.</p>

            <h2>5. Согласие и его отзыв</h2>
            <p>Согласие даётся отдельным действием: установкой обязательного флажка перед отправкой формы или регистрацией. Отозвать согласие можно письмом на <a href={`mailto:${details.email}`}>{details.email}</a>. Отзыв не влияет на обработку, выполненную ранее на законном основании, и на данные, которые Оператор обязан хранить по закону или для исполнения договора.</p>

            <h2>6. Сроки хранения</h2>
            <ul>
                <li>Данные обращения без договора: до 1 года после завершения переписки.</li>
                <li>Данные аккаунта и поддержки: в течение действия договора и до 3 лет после его прекращения, если более длительный срок не установлен законом.</li>
                <li>Технические журналы безопасности: как правило, до 12 месяцев.</li>
                <li>Платёжные и бухгалтерские сведения: в сроки, установленные законодательством.</li>
            </ul>
            <p>После достижения цели данные удаляются или обезличиваются, если их дальнейшее хранение не требуется по закону.</p>

            <h2>7. Передача и поручение обработки</h2>
            <p>Данные могут передаваться в необходимом объёме хостинг-провайдерам, платёжному провайдеру, поставщикам email и push-уведомлений, Telegram при добровольной привязке аккаунта, а также государственным органам в предусмотренных законом случаях. Получатели обязаны обеспечивать конфиденциальность и безопасность данных.</p>

            <h2>8. Локализация и трансграничная передача</h2>
            <p>При сборе персональных данных граждан Российской Федерации их первичная запись, систематизация, накопление, хранение, уточнение и извлечение выполняются с использованием баз данных на территории Российской Федерации, кроме прямо предусмотренных законом случаев.</p>
            <p>Трансграничная передача не выполняется без наличия законного основания и выполнения обязательных предварительных процедур. Переход по внешней ссылке Telegram или платёжного провайдера регулируется также документами соответствующего сервиса.</p>

            <h2>9. Права субъекта</h2>
            <p>Пользователь вправе запросить сведения об обработке, уточнение, блокирование или удаление данных, отозвать согласие и обжаловать действия Оператора. Запрос направляется на email Оператора и должен позволять идентифицировать заявителя.</p>

            <h2>10. Защита данных</h2>
            <p>Оператор применяет разграничение доступа, защищённые соединения, резервное копирование, журналирование и иные организационные и технические меры, соответствующие характеру обрабатываемых данных.</p>

            <h2>11. Изменения и контакты</h2>
            <p>Актуальная редакция всегда размещается на этой странице. Вопросы и требования по персональным данным направляются на <a href={`mailto:${details.email}`}>{details.email}</a> с темой «Персональные данные».</p>
        </>
    );
}

function LegalPage({ type = 'offer' }) {
    const isPrivacy = type === 'privacy';
    return (
        <PageFrame>
            <section className="legal-section">
                <div className="container legal-container">
                    <p className="eyebrow">Документы</p>
                    <h1 className="legal-title">{isPrivacy ? 'Политика обработки персональных данных' : 'Публичная оферта'}</h1>
                    <div className="legal-body">{isPrivacy ? <PrivacyDocument /> : <OfferDocument />}</div>
                </div>
            </section>
        </PageFrame>
    );
}

function LegalInfoPage() {
    const details = legal();
    return (
        <PageFrame>
            <section className="legal-section">
                <div className="container legal-container">
                    <p className="eyebrow">Правовая информация</p>
                    <h1 className="legal-title">Реквизиты и порядок обращений</h1>
                    <div className="legal-body">
                        <LegalRequisites />
                        <h2>Поддержка</h2>
                        <p>Обращения принимаются по email <a href={`mailto:${details.email}`}>{details.email}</a>. Telegram <a href="https://t.me/auralith_support">@auralith_support</a> используется как дополнительный оперативный канал и не заменяет email для юридически значимых обращений.</p>
                        <h2>Как направить претензию</h2>
                        <p>Укажите ФИО или идентификатор аккаунта, контактный email, дату и сумму оплаты, описание обстоятельств и требование. Приложите чек и материалы, подтверждающие обращение. Претензию можно направить по email или по адресу для корреспонденции.</p>
                        <h2>Документы</h2>
                        <p><a href={routes().offer}>Публичная оферта</a>, <a href={routes().privacy}>Политика обработки персональных данных</a>, <a href={routes().cookies}>Политика использования cookie</a>.</p>
                    </div>
                </div>
            </section>
        </PageFrame>
    );
}

function CookiePolicyPage() {
    return (
        <PageFrame>
            <section className="legal-section">
                <div className="container legal-container">
                    <p className="eyebrow">Документы</p>
                    <h1 className="legal-title">Политика использования cookie</h1>
                    <div className="legal-body">
                        <p>Редакция действует с 8 июня 2026 года. Cookie — небольшие фрагменты данных, которые сайт сохраняет в браузере для работы сессии, безопасности и выбранных настроек.</p>
                        <h2>1. Необходимые cookie</h2>
                        <p>Используются без отключения, поскольку без них не работают вход, защита форм и сохранение выбора: сессионный cookie Laravel, XSRF-TOKEN и локальная запись auralith_cookie_preferences. Сессионные cookie обычно действуют до окончания сессии или срока, установленного сервером; выбор cookie хранится до его удаления пользователем.</p>
                        <h2>2. Функциональные cookie</h2>
                        <p>Могут сохранять дополнительные настройки интерфейса и уведомлений. Они включаются только после согласия или явного действия пользователя, например подключения уведомлений.</p>
                        <h2>3. Аналитические cookie</h2>
                        <p>На момент публикации внешняя аналитика по умолчанию отключена. Если она будет подключена, соответствующие технологии начнут работать только после согласия, а политика будет дополнена названием поставщика и сроками хранения.</p>
                        <h2>4. Третьи лица</h2>
                        <p>При переходе в Telegram или открытии платёжного интерфейса соответствующие поставщики могут применять собственные cookie по своим правилам. До такого действия сайт не устанавливает их необязательные cookie от имени пользователя.</p>
                        <h2>5. Управление согласием</h2>
                        <p>В баннере можно принять все категории, оставить только необходимые или настроить выбор. Изменить решение можно после удаления сохранённых данных сайта средствами браузера; при следующем посещении сайт запросит выбор заново.</p>
                        <h2>6. Контакты</h2>
                        <p>Вопросы о cookie направляются на <a href={`mailto:${legal().email}`}>{legal().email}</a>.</p>
                    </div>
                </div>
            </section>
        </PageFrame>
    );
}

function AuthShell({ eyebrow, title, hint, children }) {
    const r = routes();
    return (
        <div className="auth-wrap">
            <a href={r.home} className="brand"><BrandMark /><span>Auralith</span></a>
            <div className="card">
                <p className="eyebrow">{eyebrow}</p>
                <h1>{title}</h1>
                {hint && <p className="hint">{hint}</p>}
                <Alerts />
                {children}
            </div>
            <CookieBanner />
        </div>
    );
}

function Alerts() {
    const { errors = [], success, telegramError } = readProps();
    return (
        <>
            {errors.length > 0 && <div className="alert">{errors.map((e) => <p key={e}>{e}</p>)}</div>}
            {success && <div className="alert" style={{ borderColor: 'rgba(84,168,127,.5)', background: 'rgba(63,128,92,.18)' }}>{success}</div>}
            {telegramError === 'expired' && <div className="alert">Ссылка входа через Telegram устарела или уже использована. Нажмите «Войти через Telegram» ещё раз.</div>}
        </>
    );
}

function LoginPage() {
    const r = routes();
    const [sessionKey, setSessionKey] = useState('');
    const [hint, setHint] = useState('');
    useEffect(() => {
        if (!sessionKey) return undefined;
        const timer = setInterval(async () => {
            const response = await fetch(`${r.telegramStatus}?session_key=${encodeURIComponent(sessionKey)}`, { headers: { Accept: 'application/json' }, credentials: 'same-origin' }).catch(() => null);
            const data = response ? await response.json().catch(() => ({})) : {};
            if (data.authenticated && data.redirect) window.location.href = data.redirect;
        }, 1000);
        return () => clearInterval(timer);
    }, [sessionKey]);
    const startTelegram = () => {
        const key = `s${Math.random().toString(36).replace(/[^a-z0-9]/g, '').slice(2, 18)}${Date.now().toString(36)}`;
        setSessionKey(key);
        setHint('Откройте Telegram и подтвердите вход. Если команда не подставилась, отправьте её вручную.');
        const url = `https://t.me/auralithaccessbot?start=login_${key}`;
        /Android|iPhone|iPad|iPod/i.test(navigator.userAgent) ? window.location.assign(url) : window.open(url, '_blank', 'noopener');
    };
    return (
        <AuthShell eyebrow="Личный кабинет" title="Вход в профиль">
            <form method="post" action={r.loginSubmit}>
                <input type="hidden" name="_token" value={csrf()} />
                <label>Имя пользователя<input type="text" name="username" placeholder="Ваш логин" required autoFocus /></label>
                <label>Пароль<input type="password" name="password" placeholder="Ваш пароль" required /></label>
                <button type="submit">Войти</button>
            </form>
            <p className="demo-text" style={{ marginTop: 10 }}><a href={r.forgot} style={{ color: '#6b93c0' }}>Забыли логин или пароль?</a></p>
            <div className="divider"><span>или</span></div>
            <div className="auth-note"><strong>Вход через Telegram</strong><span>Нажмите кнопку ниже и подтвердите вход в боте.</span></div>
            <button type="button" className="tg-login-btn" onClick={startTelegram}>Войти через Telegram</button>
            {hint && <div style={{ textAlign: 'center', color: '#8a94a6', fontSize: '.82rem', marginTop: 8 }}>{hint}</div>}
            {sessionKey && <div className="manual-command"><span>Команда для ручной отправки боту:</span><code>/start login_{sessionKey}</code></div>}
            <p className="demo-text">Нет аккаунта? <a href={r.register} style={{ color: '#6b93c0' }}>Зарегистрироваться</a></p>
        </AuthShell>
    );
}

function RegisterPage() {
    const r = routes();
    return (
        <AuthShell eyebrow="Создать аккаунт" title="Регистрация" hint="Заполните данные для создания профиля.">
            <div className="auth-note"><strong>Telegram-вход подключается после регистрации</strong><span>Создайте аккаунт, затем запустите бота и привяжите Telegram в профиле.</span></div>
            <form method="post" action={r.registerSubmit}>
                <input type="hidden" name="_token" value={csrf()} />
                <label>Имя пользователя<input type="text" name="username" placeholder="Только буквы, цифры и _" required autoFocus /></label>
                <label>Пароль<input type="password" name="password" placeholder="Минимум 8 символов" required /></label>
                <label>Повторите пароль<input type="password" name="password_confirmation" placeholder="Повторите пароль" required /></label>
                <label className="consent-check">
                    <input type="checkbox" name="privacy_consent" value="1" required />
                    <span>Я согласен на обработку персональных данных по <a href={r.privacy} target="_blank" rel="noreferrer">Политике обработки персональных данных</a>.</span>
                </label>
                <label className="consent-check">
                    <input type="checkbox" name="offer_acceptance" value="1" required />
                    <span>Я принимаю условия <a href={r.offer} target="_blank" rel="noreferrer">Публичной оферты</a>.</span>
                </label>
                <button type="submit">Создать аккаунт</button>
            </form>
            <p className="demo-text">Уже есть аккаунт? <a href={r.login} style={{ color: '#6b93c0' }}>Войти</a></p>
        </AuthShell>
    );
}

function SimpleAuthPage() {
    const props = readProps();
    const r = routes();
    const [status, setStatus] = useState(props.recoveryStarted ? 'Ждём подтверждение в Telegram...' : '');
    useEffect(() => {
        if (!props.recoveryStarted || !props.statusUrl) return undefined;
        const timer = setInterval(async () => {
            const response = await fetch(props.statusUrl, { headers: { Accept: 'application/json' }, credentials: 'same-origin' }).catch(() => null);
            const data = response ? await response.json().catch(() => ({})) : {};
            if (data.confirmed && data.redirect) {
                window.location.href = data.redirect;
            } else if (data.expired) {
                setStatus(data.message || 'Запрос восстановления истёк.');
                clearInterval(timer);
            }
        }, 1500);
        return () => clearInterval(timer);
    }, []);
    if (rootEl.dataset.page === 'reset-access') {
        return (
            <AuthShell eyebrow="Доступ подтверждён" title="Новый пароль" hint={props.username ? `Ваш логин: ${props.username}` : 'Задайте новый пароль для аккаунта.'}>
                <form method="post" action={props.action}>
                    <input type="hidden" name="_token" value={csrf()} />
                    <label>Новый пароль<input type="password" name="password" required autoComplete="new-password" /></label>
                    <label>Повторите пароль<input type="password" name="password_confirmation" required autoComplete="new-password" /></label>
                    <button type="submit">Сохранить пароль</button>
                </form>
                <p className="demo-text"><a href="https://t.me/auralith_support" style={{ color: '#6b93c0' }}>Написать в поддержку</a></p>
            </AuthShell>
        );
    }
    return (
        <AuthShell eyebrow="Восстановление" title="Забыли доступ?" hint="Если к аккаунту привязан Telegram, мы подтвердим личность через бота.">
            {props.recoveryStarted ? (
                <>
                    <div className="auth-note"><strong>Подтвердите восстановление в Telegram</strong><span>Откройте бота и подтвердите восстановление. Ссылка активна {props.expiresIn || 15} минут.</span></div>
                    <a className="tg-login-btn" href={props.tgDeepLink || props.deepLink}>Открыть Telegram</a>
                    <div className="manual-command"><span>Команда для ручной отправки боту:</span><code>{props.manualCommand}</code></div>
                    <div className="auth-status">{status}</div>
                </>
            ) : (
                <>
                    <form method="post" action={r.forgotSubmit}>
                        <input type="hidden" name="_token" value={csrf()} />
                        <label>Логин или Telegram ID<input type="text" name="identifier" placeholder="user123 или 701337001" required autoFocus /></label>
                        <button type="submit">Продолжить через Telegram</button>
                    </form>
                    <p className="demo-text"><a href={r.login} style={{ color: '#6b93c0' }}>Вернуться ко входу</a></p>
                </>
            )}
        </AuthShell>
    );
}

function AppLoginPage() {
    const props = readProps();
    return (
        <AuthShell eyebrow={`Auralith ${props.client || 'App'}`} title="Вход в приложение">
            {props.invalidLink ? <div className="alert">Некорректная ссылка входа. Откройте вход из приложения Auralith.</div> : (
                <>
                    {props.confirmed && <div className="alert" style={{ borderColor: 'rgba(84,168,127,.5)', background: 'rgba(63,128,92,.18)' }}>Вход подтверждён. Вернитесь в приложение Auralith.</div>}
                    {!props.confirmed && <form method="post" action={props.action}>
                        <input type="hidden" name="_token" value={csrf()} />
                        <input type="hidden" name="session_key" value={props.sessionKey || ''} />
                        <input type="hidden" name="client" value={(props.client || 'app').toLowerCase()} />
                        {!props.authenticated && <><label>Логин<input type="text" name="login" required autoFocus /></label><label>Пароль<input type="password" name="password" required /></label></>}
                        <button type="submit">Войти в приложение Auralith</button>
                    </form>}
                </>
            )}
        </AuthShell>
    );
}

function SubscriptionImportPage() {
    const props = readProps();
    return (
        <main className="wrap">
            <a href={routes().home} className="brand"><BrandMark /><span>Auralith</span></a>
            <section className="card">
                <p className="eyebrow">Импорт подписки</p>
                <h1>Откройте конфигурацию в приложении</h1>
                <p className="lead">Выберите установленный клиент. Браузер передаст ссылку приложению, а подписка добавится автоматически.</p>
                <div className="url-box"><span>Ссылка конфигурации · {props.nodeName}</span><code>{props.subscriptionUrl}</code></div>
                <div className="apps">
                    {(props.apps || []).map((app) => <article className="app-card" key={app.name}><strong>{app.name}</strong><a href={app.href} className="import-btn">Открыть</a><div className="fallback"><a href={app.ios}>iOS</a><a href={app.android}>Android</a></div></article>)}
                </div>
                <p className="note">Если приложение не открылось, установите клиент и повторите импорт.</p>
                <p className="legal-use-note">Конфигурация предназначена только для подключения к собственной или разрешённой инфраструктуре. Использование для обхода ограничений доступа и иных противоправных целей запрещено.</p>
                <a className="raw-link" href={props.rawUrl}>Открыть raw-конфигурацию</a>
            </section>
            <CookieBanner />
        </main>
    );
}

const pages = {
    landing: LandingPage,
    b2b: B2BPage,
    faq: FAQPage,
    offer: (props) => <LegalPage {...props} type="offer" />,
    privacy: (props) => <LegalPage {...props} type="privacy" />,
    'legal-info': LegalInfoPage,
    'cookie-policy': CookiePolicyPage,
    login: LoginPage,
    register: RegisterPage,
    'forgot-access': SimpleAuthPage,
    'reset-access': SimpleAuthPage,
    'app-login': AppLoginPage,
    'subscription-import': SubscriptionImportPage,
};

if (rootEl) {
    document.getElementById('legal-static-fallback')?.remove();
    const props = readProps();
    const Page = pages[rootEl.dataset.page] || LandingPage;
    createRoot(rootEl).render(<Page {...props} />);
}
