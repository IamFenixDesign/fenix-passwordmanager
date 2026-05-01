const detectResourceName = () => {
    if (typeof GetParentResourceName === 'function') {
        try {
            const name = GetParentResourceName();
            if (name) return name;
        } catch (_) {}
    }

    const candidates = [
        window.resourceName,
        window.location?.hostname,
        window.location?.host,
        document.referrer ? new URL(document.referrer).hostname : null,
    ].filter(Boolean);

    for (const candidate of candidates) {
        const cleaned = String(candidate)
            .replace(/^https?:\/\//, '')
            .replace(/^cfx-nui-/, '')
            .replace(/:\d+$/, '')
            .split('/')[0];

        if (cleaned && cleaned !== 'nui-game-internal') {
            return cleaned;
        }
    }

    return 'fenix-passwordsmanager';
};

const resourceName = detectResourceName();
const isStandaloneNui = (() => {
    try {
        const topLevel = window.top === window.self;
        const hasReferrer = !!document.referrer;
        const inFrame = !!window.frameElement;
        return topLevel && !hasReferrer && !inFrame;
    } catch (_) {
        return true;
    }
})();

if (isStandaloneNui) {
    document.documentElement.classList.add('standalone-hidden');
    document.body.classList.add('standalone-hidden');
}

const state = {
    activeTab: 'new',
    entries: [],
    currentEntry: null,
    theme: 'light',
    security: {
        enabled: false,
        unlocked: false,
        usesLbPhonePin: false,
        requireUnlockForEdit: false,
        requireUnlockToRevealPassword: false,
    },
};

const appRootEl = document.getElementById('app');
const fabSaveBtn = document.getElementById('fab-save');
const addModal = document.getElementById('add-modal');
const closeAddBtn = document.getElementById('close-add');
const tabs = document.querySelectorAll('.tab');
const panels = {
    new: document.getElementById('tab-new'),
    manage: document.getElementById('tab-manage'),
};
const createForm = document.getElementById('create-form');
const editForm = document.getElementById('edit-form');
const listEl = document.getElementById('entry-list');
const emptyStateEl = document.getElementById('empty-state');
const entryCountEl = document.getElementById('entry-count');
const modal = document.getElementById('modal');
const modalTitle = document.getElementById('modal-title');
const closeModalBtn = document.getElementById('close-modal');
const deleteEntryBtn = document.getElementById('delete-entry');
const themeStatusEl = document.getElementById('theme-status');
const securityModal = document.getElementById('security-modal');
const securityForm = document.getElementById('security-form');
const securityPinInput = document.getElementById('security-pin');
const securitySubtitle = document.getElementById('security-subtitle');

const postToNui = async (targetResource, eventName, data) => {
    const response = await fetch(`https://${targetResource}/${eventName}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data),
    });

    const text = await response.text();

    try {
        return text ? JSON.parse(text) : { ok: true };
    } catch (_) {
        return { ok: response.ok, raw: text };
    }
};

const nui = async (eventName, data = {}) => {
    const fallbackNames = Array.from(new Set([
        resourceName,
        window.resourceName,
        'fenix-passwordsmanager',
        'lb-passwords',
        'lb-passwordmanager',
    ].filter(Boolean)));

    let lastError = null;

    for (const targetResource of fallbackNames) {
        try {
            return await postToNui(targetResource, eventName, data);
        } catch (error) {
            lastError = error;
        }
    }

    console.error('NUI fetch failed', lastError);
    return { ok: false, message: 'Could not connect to the NUI resource.' };
};

const showToast = (message) => {
    const toast = document.createElement('div');
    toast.className = 'toast';
    toast.textContent = message;
    document.body.appendChild(toast);
    setTimeout(() => toast.remove(), 2200);
};

const themeFromSettings = (settings) => settings?.display?.theme || settings?.theme;

const setTheme = (theme = 'light') => {
    const normalized = theme === 'dark' ? 'dark' : 'light';
    const root = document.documentElement;
    state.theme = normalized;

    root.dataset.theme = normalized;
    document.body.dataset.theme = normalized;
    if (appRootEl) {
        appRootEl.dataset.theme = normalized;
    }

    root.classList.toggle('dark', normalized === 'dark');
    root.classList.toggle('light', normalized !== 'dark');
    root.classList.toggle('theme-dark', normalized === 'dark');
    root.classList.toggle('theme-light', normalized !== 'dark');

    document.body.classList.toggle('dark', normalized === 'dark');
    document.body.classList.toggle('light', normalized !== 'dark');
    document.body.classList.toggle('theme-dark', normalized === 'dark');
    document.body.classList.toggle('theme-light', normalized !== 'dark');

    if (themeStatusEl) {
        themeStatusEl.textContent = normalized === 'dark' ? 'Dark Appearance' : 'Light Appearance';
    }
};

const syncTheme = async () => {
    const response = await nui('pm:getTheme');
    setTheme(response?.theme || 'light');
};

let hasFastSettingsBridge = false;

const openAddModal = () => {
    if (!addModal) return;
    addModal.classList.remove('hidden');
    addModal.setAttribute('aria-hidden', 'false');
    const first = document.getElementById('create-username');
    if (first) first.focus();
};

const closeAddModal = () => {
    if (!addModal) return;
    addModal.classList.add('hidden');
    addModal.setAttribute('aria-hidden', 'true');
    if (createForm) createForm.reset();
};

const setTab = (tab) => {
    state.activeTab = tab;
    tabs.forEach((button) => {
        const active = button.dataset.tab === tab;
        button.classList.toggle('active', active);
        button.setAttribute('aria-selected', String(active));
    });
    Object.entries(panels).forEach(([key, panel]) => {
        if (!panel) return;
        panel.classList.toggle('active', key === tab);
    });
};

const maskPassword = (value) => {
    if (!value) return 'No password';
    return '•'.repeat(Math.max(6, Math.min(value.length, 14)));
};

const escapeHtml = (text) => String(text ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');

const openSecurityModal = (reason) => {
    if (!state.security.enabled) return;

    securityModal.classList.remove('hidden');
    if (securitySubtitle) {
        securitySubtitle.textContent = reason === 'reveal'
            ? 'Use your LB Phone PIN to reveal the saved password.'
            : reason === 'edit'
                ? 'Use your LB Phone PIN to edit this entry.'
                : 'Use your hone PIN to open Password Manager.';
    }
    if (securityPinInput) {
        securityPinInput.value = '';
        securityPinInput.focus();
    }
};

const closeSecurityModal = () => {
    securityModal.classList.add('hidden');
    if (securityPinInput) {
        securityPinInput.value = '';
    }
};

const applySecurityConfig = (config) => {
    state.security = {
        ...state.security,
        ...(config || {}),
        enabled: config?.enabled === true,
        unlocked: config?.unlocked === true,
    };
};

const fetchSecurityConfig = async () => {
    const response = await nui('pm:getSecurityConfig');
    applySecurityConfig(response || {});
    return state.security;
};

const ensureUnlocked = async (reason = 'open') => {
    await fetchSecurityConfig();
    if (!state.security.enabled || state.security.unlocked) {
        return true;
    }

    openSecurityModal(reason);
    return false;
};

const renderList = () => {
    if (entryCountEl) {
        entryCountEl.textContent = `${state.entries.length} items`;
    }
    listEl.innerHTML = '';
    emptyStateEl.style.display = state.entries.length ? 'none' : 'block';

    state.entries.forEach((entry) => {
        const card = document.createElement('button');
        card.type = 'button';
        card.className = 'entry-card';
        card.innerHTML = `
            <div class="entry-top">
                <div>
                    <div class="entry-app">${escapeHtml(entry.app_name)}</div>
                    <div class="entry-user">${escapeHtml(entry.username)}</div>
                </div>
                <div class="meta-pill">Edit</div>
            </div>
            <div class="entry-password">${maskPassword(entry.password)}</div>
            <div class="entry-bottom">
                <div class="entry-user">${entry.notes ? 'Notes saved' : 'No notes'}</div>
                <div class="entry-user">${entry.updated_at ? 'Updated' : 'Stored'}</div>
            </div>
        `;

        card.addEventListener('click', async () => {
            if (state.security.requireUnlockForEdit) {
                const unlocked = await ensureUnlocked('edit');
                if (!unlocked) return;
            }
            openModal(entry);
        });
        listEl.appendChild(card);
    });
};

const openModal = (entry) => {
    state.currentEntry = entry;
    modal.classList.remove('hidden');
    modalTitle.textContent = entry.app_name || 'Entry';

    editForm.id.value = entry.id;
    editForm.username.value = entry.username || '';
    editForm.app_name.value = entry.app_name || '';
    editForm.password.value = entry.password || '';
    editForm.notes.value = entry.notes || '';

    const toggle = editForm.querySelector('.toggle-password');
    if (toggle) {
        toggle.textContent = 'Show';
    }
    const passwordInput = editForm.password;
    if (passwordInput) {
        passwordInput.type = 'password';
    }
};

const closeModal = () => {
    state.currentEntry = null;
    modal.classList.add('hidden');
};

const hydrateEntries = (entries) => {
    state.entries = Array.isArray(entries) ? entries : [];
    renderList();
};

const loadEntries = async () => {
    const entries = await nui('pm:getEntries');
    hydrateEntries(Array.isArray(entries) ? entries : []);
};

const loadTheme = syncTheme;

createForm.addEventListener('submit', async (event) => {
    event.preventDefault();

    const data = Object.fromEntries(new FormData(createForm).entries());
    const response = await nui('pm:createEntry', data);

    if (!response.ok) {
        showToast(response.message || 'Could not save the entry.');
        return;
    }

    hydrateEntries(response.entries);
    createForm.reset();
    closeAddModal();
    showToast('Entry saved');
});

editForm.addEventListener('submit', async (event) => {
    event.preventDefault();

    const data = Object.fromEntries(new FormData(editForm).entries());
    const response = await nui('pm:updateEntry', data);

    if (!response.ok) {
        showToast(response.message || 'Could not update the entry.');
        return;
    }

    hydrateEntries(response.entries);
    closeModal();
    showToast('Entry updated');
});

deleteEntryBtn.addEventListener('click', async () => {
    if (!state.currentEntry) return;

    const response = await nui('pm:deleteEntry', { id: state.currentEntry.id });

    if (!response.ok) {
        showToast(response.message || 'Could not delete the entry.');
        return;
    }

    hydrateEntries(response.entries);
    closeModal();
    showToast('Entry deleted');
});

securityForm.addEventListener('submit', async (event) => {
    event.preventDefault();

    const pin = securityPinInput?.value?.trim() || '';
    const response = await nui('pm:unlockWithPhonePin', { pin });

    if (!response?.ok) {
        showToast(response?.message || 'Could not unlock Password Manager.');
        return;
    }

    applySecurityConfig({ ...state.security, unlocked: true });
    closeSecurityModal();
    await loadEntries();
});

closeModalBtn.addEventListener('click', closeModal);
document.querySelector('#modal .modal-backdrop').addEventListener('click', closeModal);

tabs.forEach((button) => {
    button.addEventListener('click', () => setTab(button.dataset.tab));
});

if (fabSaveBtn) {
    fabSaveBtn.addEventListener('click', openAddModal);
}
if (closeAddBtn) {
    closeAddBtn.addEventListener('click', closeAddModal);
}
if (addModal) {
    const backdrop = addModal.querySelector('.modal-backdrop');
    if (backdrop) backdrop.addEventListener('click', closeAddModal);
}

document.querySelectorAll('.toggle-password').forEach((button) => {
    button.addEventListener('click', async () => {
        const input = button.parentElement.querySelector('input');
        if (!input) return;

        const wantsReveal = input.type === 'password';
        if (wantsReveal && input.id === 'edit-password' && state.security.requireUnlockToRevealPassword) {
            const unlocked = await ensureUnlocked('reveal');
            if (!unlocked) return;
        }

        input.type = wantsReveal ? 'text' : 'password';
        button.textContent = wantsReveal ? 'Hide' : 'Show';
    });
});

document.addEventListener('visibilitychange', () => {
    if (!document.hidden) {
        if (!hasFastSettingsBridge) syncTheme();
    }
});

window.addEventListener('focus', () => {
    if (!hasFastSettingsBridge) syncTheme();
});

setInterval(() => {
    if (!document.hidden && !hasFastSettingsBridge) {
        syncTheme();
    }
}, 30000);

window.addEventListener('message', async (event) => {
    if (event.data?.type === 'refreshEntries') {
        loadEntries();
    }

    if (event.data?.type === 'setTheme' && event.data?.theme) {
        setTheme(event.data.theme);
    }

    if (event.data?.type === 'settingsUpdated') {
        const nextTheme = themeFromSettings(event.data.settings);
        if (nextTheme) setTheme(nextTheme);
    }

    if (event.data?.type === 'pm:securityState') {
        applySecurityConfig(event.data);
        if (event.data.unlocked) {
            closeSecurityModal();
            await loadEntries();
        } else if (event.data.reason === 'open') {
            openSecurityModal('open');
        }
    }
});

window.__FENIX_PASSWORDSMANAGER_RESOURCE__ = resourceName;

const settingsChangeFn = globalThis.onSettingsChange || globalThis.OnSettingsChange;
const getSettingsFn = globalThis.getSettings || globalThis.GetSettings;

if (typeof settingsChangeFn === 'function') {
    hasFastSettingsBridge = true;
    settingsChangeFn((settings) => {
        const theme = themeFromSettings(settings);
        if (theme) setTheme(theme);
    });
}

if (typeof getSettingsFn === 'function') {
    hasFastSettingsBridge = true;
    getSettingsFn().then((settings) => {
        const theme = themeFromSettings(settings);
        if (theme) setTheme(theme);
    }).catch(() => {});
}

loadTheme();
fetchSecurityConfig().then((security) => {
    if (!security.enabled || security.unlocked) {
        loadEntries();
    } else {
        openSecurityModal('open');
    }
});

setTab('manage');
