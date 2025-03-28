serve:
  zola serve --drafts

tex:
  fd source.md | entr -p node renderKatex.js /_

with-tex:
  just serve &
  just tex

comments:
  #!/usr/bin/env nu
  http get $"https://webmention.io/api/mentions.jf2?token=($env.WEBMENTION_IO_TOKEN)" | save -f data/comments.json
