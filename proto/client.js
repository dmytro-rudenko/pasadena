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

  document.addEventListener('click', function (event) {
    var option = event.target.closest('[data-choice]');
    if (!option) return;
    var multi = option.closest('[data-multiselect]');
    if (!multi) {
      var siblings = option.parentElement.querySelectorAll('[data-choice].selected');
      for (var index = 0; index < siblings.length; index++) siblings[index].classList.remove('selected');
      option.classList.add('selected');
    } else {
      option.classList.toggle('selected');
    }
    post({
      type: 'click',
      choice: option.getAttribute('data-choice'),
      text: (option.innerText || '').trim().slice(0, 200),
      screen: location.pathname,
      selected: option.classList.contains('selected'),
    });
  });

  // Polling, not a socket: the whole server→browser channel this needs is
  // "something changed". One number a second is cheaper to write than to read.
  var stamp = null;
  setInterval(function () {
    fetch('/_sdd/poll')
      .then(function (response) { return response.ok ? response.json() : null; })
      .then(function (data) {
        if (!data) return;
        if (stamp === null) { stamp = data.stamp; return; }
        if (data.stamp !== stamp) location.reload();
      })
      .catch(function () { /* server stopped */ });
  }, 1000);
})();
