let currentSection = 'dashboard';
let userRank = 0;

window.addEventListener('message', (event) => {
    const data = event.data;

    if (data.action === 'open') {
        document.getElementById('app-container').style.display = 'flex';
        userRank = data.rank;
        updateUI(data);
    } else if (data.action === 'close') {
        document.getElementById('app-container').style.display = 'none';
    } else if (data.action === 'update') {
        updateUI(data);
    }
});

function updateUI(data) {
    if (userRank >= 8) {
        document.getElementById('admin-tab').style.display = 'flex';
    }

    // Update Stats
    document.getElementById('active-tracks').innerText = data.activeTracksCount || 0;
    document.getElementById('pending-permits').innerText = data.pendingCount || 0;

    // Render Components
    renderTargetCards(data.permits || []);
    renderActivity(data.activities || []);
    renderPermits(data.permits || []);
    if (userRank >= 8) renderAdminPermits(data.pendingPermits || []);
}

function showSection(section) {
    document.getElementById(`${currentSection}-section`).style.display = 'none';
    document.getElementById(`${section}-section`).style.display = 'block';

    // Update nav links
    const navItems = document.querySelectorAll('.nav-item');
    navItems.forEach(item => {
        if (item.title && item.title.toLowerCase().includes(section === 'dashboard' ? 'dashboard' : (section === 'permits' ? 'beschlüsse' : 'admin'))) {
            item.classList.add('active');
        } else if (section === 'dashboard' && item.title === 'Dashboard') {
            item.classList.add('active');
        } else {
            item.classList.remove('active');
        }
    });

    document.getElementById('section-title').innerText = section.charAt(0).toUpperCase() + section.slice(1);
    currentSection = section;
}

function renderTargetCards(permits) {
    const grid = document.getElementById('active-targets-grid');
    const activePermits = permits.filter(p => p.status === 'approved').slice(0, 4);

    if (activePermits.length === 0) {
        grid.innerHTML = '<p style="color: var(--text-muted); font-size: 14px;">Keine aktiven Ortungen</p>';
        return;
    }

    grid.innerHTML = activePermits.map(p => `
        <div class="target-card" onclick="startTracking('${p.number}')">
            <div class="symbol">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"></path>
                </svg>
                <div class="symbol-text">TARGET</div>
                <div class="badge badge-green" style="margin-left: auto;">ACTIVE</div>
            </div>
            <div class="price">${p.number}</div>
            <div class="change plus">Gültig bis ${p.expiry}</div>
            <svg class="sparkline" viewBox="0 0 100 40">
                <path d="M0,20 Q25,5 50,25 T100,20" fill="none" stroke="#03a66d" stroke-width="2"></path>
            </svg>
        </div>
    `).join('');
}

function renderActivity(activities) {
    const container = document.getElementById('activity-logs');
    container.innerHTML = activities.slice(0, 6).map(act => `
        <tr>
            <td class="phone-col">
                <div class="phone-icon">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                        <path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72 12.84 12.84 0 0 0 .7 2.81 2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45 12.84 12.84 0 0 0 2.81.7A2 2 0 0 1 22 16.92z"></path>
                    </svg>
                </div>
                <span>${act.number}</span>
            </td>
            <td>Ortungsantrag</td>
            <td>${act.time}</td>
            <td style="text-align: right;">
                <span class="badge ${getStatusClass(act.status)}">${act.statusLabel}</span>
            </td>
        </tr>
    `).join('');
}

function renderPermits(permits) {
    const container = document.getElementById('permits-list');
    container.innerHTML = permits.map(p => `
        <tr>
            <td>${p.number}</td>
            <td>${p.requester || 'Unbekannt'}</td>
            <td>${p.expiry || '---'}</td>
            <td><span class="badge ${getStatusClass(p.status)}">${p.statusLabel}</span></td>
            <td style="text-align: right; display: flex; gap: 8px; justify-content: flex-end;">
                ${p.status === 'approved' ? `<button class="btn-binance" style="width: auto; padding: 4px 12px; font-size: 12px;" onclick="startTracking('${p.number}')">Ortung</button>` : ''}
                ${(p.status === 'approved' && userRank >= 8) ? `<button class="btn-binance btn-secondary" style="width: auto; padding: 4px 12px; font-size: 12px;" onclick="revokePermit('${p.number}')">Widerrufen</button>` : ''}
                ${p.status !== 'approved' ? '---' : ''}
            </td>
        </tr>
    `).join('');
}

function renderAdminPermits(pendings) {
    const container = document.getElementById('admin-permits');
    container.innerHTML = pendings.map(p => `
        <tr>
            <td>${p.requester}</td>
            <td>${p.number}</td>
            <td>${p.reason}</td>
            <td style="text-align: right; display: flex; gap: 8px; justify-content: flex-end;">
                <button class="btn-binance" style="width: auto; padding: 4px 12px; font-size: 12px;" onclick="approveRequest('${p.id}')">JA</button>
                <button class="btn-binance btn-secondary" style="width: auto; padding: 4px 12px; font-size: 12px;" onclick="denyRequest('${p.id}')">NEIN</button>
            </td>
        </tr>
    `).join('');
}

function getStatusClass(status) {
    if (status === 'approved') return 'badge-green';
    if (status === 'denied') return 'badge-red';
    return 'badge-yellow';
}

function startTracking(number) {
    fetch(`https://${GetParentResourceName()}/startTracking`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({ number })
    });
}

function openRequestModal() {
    document.getElementById('request-modal').style.display = 'flex';
}

function closeRequestModal() {
    document.getElementById('request-modal').style.display = 'none';
}

function submitRequest() {
    const number = document.getElementById('req-number').value;
    const reason = document.getElementById('req-reason').value;

    fetch(`https://${GetParentResourceName()}/submitRequest`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({ number, reason })
    }).then(() => {
        closeRequestModal();
        document.getElementById('req-number').value = '';
        document.getElementById('req-reason').value = '';
    });
}

function submitQuickRequest() {
    const number = document.getElementById('quick-number').value;
    if (!number) return;

    fetch(`https://${GetParentResourceName()}/submitRequest`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({ number, reason: 'Schnell-Antrag via Dashboard' })
    }).then(() => {
        document.getElementById('quick-number').value = '';
    });
}

function approveRequest(id) {
    fetch(`https://${GetParentResourceName()}/approveRequest`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({ id })
    });
}

function denyRequest(id) {
    fetch(`https://${GetParentResourceName()}/denyRequest`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({ id })
    });
}

function revokePermit(number) {
    fetch(`https://${GetParentResourceName()}/revokePermit`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({ number })
    });
}

document.onkeydown = function (evt) {
    evt = evt || window.event;
    if (evt.keyCode == 27) { // ESC
        fetch(`https://${GetParentResourceName()}/close`, { method: 'POST' });
        document.getElementById('app-container').style.display = 'none';
    }
};
