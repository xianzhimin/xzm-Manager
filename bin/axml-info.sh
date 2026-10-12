#!/system/bin/sh
# axml-info.sh <apk>  —— 纯 shell 解析 APK 的 AndroidManifest.xml
# 输出 JSON: pkg, ver, code, label, minSdk, targetSdk
# 依赖: unzip, od, awk (toybox)，函数定义需放在顶层（用 awk -f）

apk="$1"
[ -z "$apk" ] || [ ! -f "$apk" ] && { echo '{"ok":false,"error":"no apk"}'; exit 1; }

TMP="/data/local/tmp/.axml.$$"
mkdir -p "$TMP" 2>/dev/null
unzip -p "$apk" AndroidManifest.xml > "$TMP/m.bin" 2>/dev/null
[ -s "$TMP/m.bin" ] || { rm -rf "$TMP"; echo '{"ok":false,"error":"no manifest"}'; exit 1; }
od -An -v -tu1 "$TMP/m.bin" > "$TMP/bytes.txt" 2>/dev/null
rm -f "$TMP/m.bin"

cat > "$TMP/p.awk" <<'AWKEOF'
function u8(o){ return b[o] }
function u16(o){ return b[o] + b[o+1]*256 }
function u32(o){ return b[o] + b[o+1]*256 + b[o+2]*65536 + b[o+3]*16777216 }
function jesc(s){ gsub(/\\/,"\\\\",s); gsub(/"/,"\\\"",s); return s }

{
  for(i=1;i<=NF;i++){ b[n++]=$i+0 }
}
END{
  cnt=u32(16); flg=u32(24); sstr=u32(28)
  utf8 = (flg - int(flg/512)*512 >= 256) ? 1 : 0
  base = 8 + sstr
  for(i=0;i<cnt && i<4096;i++){ soff[i]=u32(36+4*i) }
  for(i=0;i<cnt && i<4096;i++){
    p=base+soff[i]
    if(utf8){
      l=u8(p); p++
      if(l>=128){ l=(l-128)*256 + u8(p); p++ }
      l2=u8(p); p++
      if(l2>=128){ l2=(l2-128)*256 + u8(p); p++ }
      str=""
      for(k=0;k<l2;k++){ str=str sprintf("%c",u8(p+k)) }
    } else {
      ln=u16(p); p+=2
      if(ln>=32768){ ln=(ln-32768)*65536 + u16(p); p+=2 }
      str=""
      for(k=0;k<ln;k++){
        c=u16(p+2*k)
        if(c<128){ str=str sprintf("%c",c) }
        else if(c<2048){ str=str sprintf("%c",192+int(c/64)) sprintf("%c",128+(c-int(c/64)*64)) }
        else { str=str sprintf("%c",224+int(c/4096)) sprintf("%c",128+(int(c/64)-int(c/64/64)*64)) sprintf("%c",128+(c-int(c/64)*64)) }
      }
    }
    S[i]=str
  }

  p = 8 + u32(12)
  pkg=""; ver=""; code=""; label=""; minsdk=""; tgtsdk=""
  while(p < n-8){
    ct=u16(p); cs=u32(p+4)
    if(cs==0) break
    if(ct==258){
      nm=u32(p+20); ele=S[nm]
      astart=u16(p+24); acount=u16(p+28); asize=20
      for(j=0;j<acount;j++){
        a = p+16+astart+j*asize
        an=u32(a+4); vt=u8(a+15); vd=u32(a+16); rv=u32(a+8)
        attr=S[an]; val=""
        if(vt==3){ val=S[vd] }
        else if(vt==16){ val=vd }
        else if(vt==17){ val=sprintf("0x%x",vd) }
        else if(vt==18){ val=(vd?"true":"false") }
        else { if(rv!=4294967295 && rv<4096) val=S[rv]; else val=vd }
        if(ele=="manifest"){
          if(attr=="package") pkg=val
          else if(attr=="versionName") ver=val
          else if(attr=="versionCode") code=val
        } else if(ele=="uses-sdk"){
          if(attr=="minSdkVersion") minsdk=val
          else if(attr=="targetSdkVersion") tgtsdk=val
        } else if(ele=="application"){
          if(attr=="label" && label=="") label=val
        }
      }
    }
    p += cs
  }
  printf "{\"ok\":true,\"pkg\":\"%s\",\"ver\":\"%s\",\"code\":\"%s\",\"label\":\"%s\",\"minSdk\":\"%s\",\"targetSdk\":\"%s\"}\n", jesc(pkg), jesc(ver), jesc(code), jesc(label), jesc(minsdk), jesc(tgtsdk)
}
AWKEOF

awk -f "$TMP/p.awk" "$TMP/bytes.txt"
rm -rf "$TMP"
