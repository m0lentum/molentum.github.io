# Gets new webmentions that haven't been fetched before
# and stores them in data/comments.json.

let old = (open data/comments.json)
let last_id = if not ($old | is-empty) {
  ($old | get wm-id | math max)
} else {
  1
}

mut data = []
mut page = 0
let url = $"https://webmention.io/api/mentions.jf2?domain=molentum.me&token=($env.WEBMENTION_IO_TOKEN)&since_id=($last_id)"
loop {
  let resp = (http get $"($url)&page=($page)" | get children)

  if ($resp | is-empty) {
    if ($page == 0) {
      print "Nothing new"
      return
    }
    break
  }

  $data = ($data | append $resp)
  $page += 1
}

# print some info about stuff we got
let replies = ($data | filter { $in.wm-property == "in-reply-to" })
print $"($replies | length) replies"
if not ($replies | is-empty) {
  print ($replies | select wm-target author.name content.text)
}
let mentions = ($data | filter { $in.wm-property == "mention-of" })
print $"($mentions | length) mentions"
if not ($mentions | is-empty) {
  print ($mentions | select wm-target author.name content.text)
}
let like_count = ($data | filter { $in.wm-property == "like-of" } | length)
print $"($like_count) likes"
let boost_count = ($data | filter { $in.wm-property == "repost-of" } | length)
print $"($boost_count) boosts"

let full_data = ($old
  | append $data
  | sort-by -r { if $in.published != null { $in.published } else { $in.wm-received }}
  | uniq-by wm-id
)
$full_data | save -f data/comments.json
