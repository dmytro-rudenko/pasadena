// Injected into every page the prototype server serves. Two jobs: record which
// option the user clicked, and reload when we write a new screen.
(function () {
  'use strict';

  function post(payload) {
    return fetch('/_sdd/event', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(payload),
    }).catch(function () { /* the server is gone; the page still works */ });
  }

  document.addEventListener('click', function (e) {
    var el = e.target.closest('[data-choice]');
    if (!el) return;
    var multi = el.closest('[data-multiselect]');
    if (!multi) {
      var siblings = el.parentElement.querySelectorAll('[data-choice].selected');
      for (var i = 0; i < siblings.length; i++) siblings[i].classList.remove('selected');
      el.classList.add('selected');
    } else {
      el.classList.toggle('selected');
    }
    post({
      type: 'click',
      choice: el.getAttribute('data-choice'),
      text: (el.innerText || '').trim().slice(0, 200),
      screen: location.pathname,
      selected: el.classList.contains('selected'),
    });
  });

  // Polling, not a socket: the whole server→browser channel this needs is
  // "something changed". One number a second is cheaper to write than to read.
  var stamp = null;
  setInterval(function () {
    fetch('/_sdd/poll')
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (d) {
        if (!d) return;
        if (stamp === null) { stamp = d.stamp; return; }
        if (d.stamp !== stamp) location.reload();
      })
      .catch(function () { /* server stopped */ });
  }, 1000);
})();
