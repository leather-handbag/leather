
1. 打开 Supabase Dashboard 的 `Authentication > Email Templates > Confirm signup`。
2. 在模板正文中加入 `{{ .Token }}`，并明确说明这是 Leather 注册验证码。
3. 保留确认链接 `{{ .ConfirmationURL }}` 作为邮件客户端不便输入验证码时的备用方式。
4. 确认 `Authentication > URL Configuration` 中包含正式 GitHub Pages 地址：
   `https://leather-handbag.github.io/LeatherSS/`。
5. 在测试账号上验证验证码过期、重新发送和重复邮箱提示后再开放注册。

示例正文：

```html
<p>你的 Leather 注册验证码是：</p>
<p style="font-size:24px;font-weight:700;letter-spacing:4px">{{ .Token }}</p>
<p>验证码过期后请回到注册页重新发送。</p>
<p><a href="{{ .ConfirmationURL }}">也可以点击这里确认邮箱</a></p>
```

不要在前端或仓库中保存 SMTP 密码、Supabase service role 或 GitHub OAuth
Client Secret。
