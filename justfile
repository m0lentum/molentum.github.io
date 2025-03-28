serve:
  zola serve --drafts

tex:
  fd source.md | entr -p node renderKatex.js /_

with-tex:
  just serve &
  just tex
