### Unreleased

* Add `display: []` for configuring company details that are rendered

```ruby
r = Receipts::Receipt.new(
  company: {
    name: "Example, LLC",
    address: "123 Fake Street\nNew York City, NY 10012",
    phone: "(555) 867-5309",
    email: "support@example.com",
    iban: "123456789",
    logo: File.expand_path("./examples/images/logo.png"),
    display: [:address, :phone, :email, :iban]
  },
  # ...
)
```

### 2.3.0

* Add `column_widths:` option to specify line item column widths #35

### 2.2.0

* Allow specifiying other page sizes - @excid3
* Add `logo_height:` option to specify the height of the logo image

### 2.1.0

* Add `Receipts.default_font` - @excid3

### 2.0.0

* New, consistent layouts between Receipts, Invoices, and Statements - @excid3
* PDFs can now be completely customized - @excid3
* Add line_items to Receipts - @excid3

### 1.1.2

* Update design to give more room for longer product names, addresses, etc - @excid3

### 1.1.1

* [FIX] Use `URI.parse().open` instead - @excid3 @reckerswartz
* Add I18n notes to the readme - @excid3 @reckerswartz
* Add standardrb formatting - @excid3
* Add GitHub Actions for standardrb and tests - @excid3

### 1.1.0

* [NEW] Add Statements - @anquinn

### 1.0.3

* [FIX] Fixes typo introduced in 1.0.2

### 1.0.2

* [NEW] Add ability to specify file-like objects for logo

### 1.0.1

* [FIX] Make tables full width

### 1.0.0

* [NEW] Invoices!
