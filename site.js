(function () {
  var btn = document.querySelector(".nav-hamburger");
  var drawer = document.querySelector(".nav-drawer");
  if (!btn || !drawer) return;

  btn.addEventListener("click", function () {
    var open = document.body.classList.toggle("nav-open");
    btn.setAttribute("aria-expanded", open ? "true" : "false");
  });

  drawer.querySelectorAll("a").forEach(function (link) {
    link.addEventListener("click", function () {
      document.body.classList.remove("nav-open");
      btn.setAttribute("aria-expanded", "false");
    });
  });
})();
