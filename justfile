serve:
  zola serve --drafts

tex:
  fd source.md | entr -p node renderKatex.js /_

with-tex:
  just serve &
  just tex

build:
  zola build

# push build results to the `pages` branch after building
publish: build
  git rm -r "[!.git]*"
  mv public/** ./
  touch .nojekyll
  echo "molentum.me" > .domains
  # echo "molentum.codeberg.page" >> .domains
  git add -A
  git commit -m "publish"
  git push origin HEAD:pages --force
  git reset --hard HEAD~1
  rm -r assets/
