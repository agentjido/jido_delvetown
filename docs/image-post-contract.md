# DelveTown image post contract

This contract was checked on 2026-10-05. The check used read-only requests. It
did not create a post.

## Evidence

The public post record at
`at://did:plc:hr6mywilgrfqqvoxo6t4ldo2/town.delve.feed.post/3mx5psvv6r22e`
contains an image. A `town.delve.feed.getPosts` query returned the source record
with this shape:

```json
{
  "$type": "town.delve.feed.post",
  "embed": {
    "$type": "town.delve.embed.images",
    "images": [
      {
        "image": {
          "$type": "blob",
          "ref": {"$link": "bafk..."},
          "mimeType": "image/jpeg",
          "size": 31795
        },
        "alt": "",
        "aspectRatio": {"width": 198, "height": 200}
      }
    ]
  }
}
```

The current DelveTown web client bundle contains its generated lexicon
validators. They define these rules:

- The post field is `embed`.
- The embed type is `town.delve.embed.images`.
- `images` is required and has a maximum length of four. The remote lexicon
  does not set a minimum length.
- Each entry has a required `image` blob and required `alt` string.
- A blob has `$type: "blob"`, a CID link in `ref`, a MIME type in `mimeType`,
  and a non-negative byte count in `size`.
- The blob accepts `image/*` and has a maximum size of 2,000,000 bytes.
- `aspectRatio` is optional. When present, it has integer `width` and `height`
  fields. Each value has a minimum of one. The lexicon does not set a maximum.
- `alt` has no minimum or maximum length in the remote lexicon. Current public
  records confirm that an empty value is accepted.

The fixture uses JSON wire names. The ProtoRune transport converts fields such
as `mimeType` and `aspectRatio` to `:mime_type` and `:aspect_ratio`. The contract
validator accepts both forms.

## Local policy boundary

These are remote protocol rules. AgentJido draft policy can require at least one
image and non-empty alt text before it stages a post. That policy must not be
described as a DelveTown protocol rule.
