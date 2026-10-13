import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;

/**
 * NameConv —— 处理压缩包条目名编码。
 * 用法:
 *   app_process ... / NameConv hex [srcCharset]        ; stdin 一行十六进制字节 → 输出解码后的 UTF-8
 *   app_process ... / NameConv fixjson [srcCharset]    ; stdin 一行 JSON 数组，修正其中 "n" 字段(非UTF8→GBK转码)
 * 说明：Windows 下打的 zip 常把文件名存成 GBK(本地码页)，直接按 UTF-8 读会乱码。
 */
public class NameConv {
    public static void main(String[] args) {
        String mode = args.length > 0 ? args[0] : "hex";
        String srcCp = (args.length > 1 && args[1] != null && !args[1].isEmpty()) ? args[1] : "GBK";
        try {
            BufferedReader br = new BufferedReader(new InputStreamReader(System.in, "ISO-8859-1"));
            StringBuilder sb = new StringBuilder();
            int c;
            while ((c = br.read()) != -1) {
                if (c == '\n' || c == '\r') break;
                sb.append((char) c);
            }
            String line = sb.toString();

            if ("fixjson".equals(mode)) {
                System.out.print(fixJson(line, srcCp));
                return;
            }

            // hex 模式
            byte[] bytes;
            String h = line.trim();
            int n = h.length() / 2;
            bytes = new byte[n];
            for (int i = 0; i < n; i++) {
                bytes[i] = (byte) Integer.parseInt(h.substring(i * 2, i * 2 + 2), 16);
            }
            System.out.print(convert(bytes, srcCp, line));
        } catch (Throwable e) {
            System.out.print("");
        }
    }

    /** 若字节不是合法 UTF-8，则用 srcCp(GBK) 解码；否则按 UTF-8。 */
    static String convert(byte[] bytes, String srcCp, String fallbackLatin1) {
        if (isValidUtf8(bytes)) {
            return new String(bytes, StandardCharsets.UTF_8);
        }
        try {
            String s = new String(bytes, Charset.forName(srcCp));
            if (s.indexOf('\uFFFD') < 0) return s;
        } catch (Throwable t) {}
        return fallbackLatin1;
    }

    /**
     * 修名单个字段。JSON 里的字符串现在已是「busybox 把 GBK 原始字节当作 latin1 再按 UTF-8 编码」
     * 的样子，例如 中文 的 GBK 字节 d6 d0 → 被当成两个字符 U+00D6 U+00D0 → UTF-8 存成 c3 96 c3 90。
     * 因此正确还原：把字符串逐字符取其码点(应都 <256)，组成原始字节，再用 GBK 解码。
     */
    static String fixName(String mangled, byte[] latin1Bytes, String srcCp) {
        // 把 JSON 字符串按 UTF-8 解码为「它原本想表达的字符」
        // busybox 把 GBK 原始字节当 latin1→UTF-8，所以 UTF-8 解码后会得到一串 <256 的字符，
        // 这些字符的码点就是原始 GBK 字节。
        String u = new String(latin1Bytes, StandardCharsets.UTF_8);
        boolean allLow = u.length() > 0;
        for (int i = 0; i < u.length(); i++) {
            if (u.charAt(i) >= 256) { allLow = false; break; }
        }
        if (allLow) {
            byte[] raw = new byte[u.length()];
            for (int i = 0; i < u.length(); i++) raw[i] = (byte) (u.charAt(i) & 0xFF);
            if (!isValidUtf8(raw)) {
                try {
                    String s = new String(raw, Charset.forName(srcCp));
                    if (s.indexOf('\uFFFD') < 0) return s;
                } catch (Throwable t) {}
            }
        }
        // 本身就是正常 UTF-8 文本 → 原样
        return u;
    }

    static boolean isValidUtf8(byte[] b) {
        int i = 0, n = b.length;
        while (i < n) {
            int c = b[i] & 0xFF;
            int need;
            if (c < 0x80) { i++; continue; }
            else if (c >= 0xC2 && c <= 0xDF) need = 1;
            else if (c >= 0xE0 && c <= 0xEF) need = 2;
            else if (c >= 0xF0 && c <= 0xF4) need = 3;
            else return false;
            for (int k = 1; k <= need; k++) {
                if (i + k >= n) return false;
                int cc = b[i + k] & 0xFF;
                if (cc < 0x80 || cc > 0xBF) return false;
            }
            i += need + 1;
        }
        return true;
    }

    /**
     * 修正 JSON 数组 [{"n":"...","s":..,"d":..},...] 里每个 n 字段。
     * 整行按 latin1 还原为字节，找到 "n":" 后到下一个未转义 '"' 之间的原始字节，
     * 做 UTF-8 校验/GBK 转码，其余原样保留。
     */
    static String fixJson(String line, String srcCp) {
        byte[] raw = line.getBytes(StandardCharsets.ISO_8859_1);
        StringBuilder out = new StringBuilder();
        int i = 0, n = raw.length;
        byte[] keyN = { '"', 'n', '"', ':', '"' };
        while (i < n) {
            if (matchAt(raw, i, keyN)) {
                out.append(new String(keyN, StandardCharsets.ISO_8859_1));
                int j = i + keyN.length;
                StringBuilder nameBuf = new StringBuilder();
                while (j < n) {
                    int c = raw[j] & 0xFF;
                    if (c == '\\' && j + 1 < n) {
                        nameBuf.append((char) c);
                        nameBuf.append((char) (raw[j + 1] & 0xFF));
                        j += 2;
                        continue;
                    }
                    if (c == '"') break;
                    nameBuf.append((char) c);
                    j++;
                }
                byte[] nameBytes = nameBuf.toString().getBytes(StandardCharsets.ISO_8859_1);
                String fixed = fixName(nameBuf.toString(), nameBytes, srcCp);
                out.append(jsonEscape(fixed));
                i = j;
                continue;
            }
            out.append((char) (raw[i] & 0xFF));
            i++;
        }
        return out.toString();
    }

    static boolean matchAt(byte[] a, int pos, byte[] pat) {
        if (pos + pat.length > a.length) return false;
        for (int k = 0; k < pat.length; k++) if (a[pos + k] != pat[k]) return false;
        return true;
    }

    static String jsonEscape(String s) {
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"': b.append("\\\""); break;
                case '\\': b.append("\\\\"); break;
                case '\n': b.append("\\n"); break;
                case '\r': b.append("\\r"); break;
                case '\t': b.append("\\t"); break;
                default:
                    if (c < 0x20) b.append(String.format("\\u%04x", (int) c));
                    else b.append(c);
            }
        }
        return b.toString();
    }
}
