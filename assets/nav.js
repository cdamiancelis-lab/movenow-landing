(function(){
  var toggle = document.querySelector('.nav-toggle');
  var links = document.getElementById('nav-links');
  if(!toggle || !links) return;

  function closeMenu(){
    links.classList.remove('is-open');
    toggle.setAttribute('aria-expanded', 'false');
  }
  function openMenu(){
    links.classList.add('is-open');
    toggle.setAttribute('aria-expanded', 'true');
  }

  toggle.addEventListener('click', function(e){
    e.stopPropagation();
    var isOpen = links.classList.contains('is-open');
    if(isOpen){ closeMenu(); } else { openMenu(); }
  });

  links.addEventListener('click', function(e){
    if(e.target.tagName === 'A'){ closeMenu(); }
  });

  document.addEventListener('click', function(e){
    if(links.classList.contains('is-open') && !links.contains(e.target) && e.target !== toggle){
      closeMenu();
    }
  });

  document.addEventListener('keydown', function(e){
    if(e.key === 'Escape'){ closeMenu(); }
  });
})();
