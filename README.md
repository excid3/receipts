![travisci](https://api.travis-ci.org/excid3/receipts.svg)

# Receipts

Receipts for your Rails application that works with any payment provider.

Check out an [example PDF receipt](https://github.com/excid3/receipts/blob/master/examples/receipt.pdf?raw=true)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'receipts'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install receipts

## Usage

Adding receipts to your application is pretty simple. All you need is a
model that stores your transaction details. In this example our
application has a model named `Charge` that we will use.

We're going to add a method called `receipt` on our model called `Charge`
that will create a new receipt for the charge using attributes from the
model.

Video Tutorial:
[GoRails Episode #51](https://gorails.com/episodes/pdf-receipts)

```ruby
# == Schema Information
#
# Table name: charges
#
#  id             :integer          not null, primary key
#  user_id        :integer
#  stripe_id      :string(255)
#  amount         :integer
#  card_last4     :string(255)
#  card_type      :string(255)
#  card_exp_month :integer
#  card_exp_year  :integer
#  uuid           :string
#  created_at     :datetime
#  updated_at     :datetime
#

class Charge < ActiveRecord::Base
  belongs_to :user
  validates :stripe_id, uniqueness: true

  def receipt
    Receipts::Receipt.new(
      id: id,
      product: "GoRails",
      company: {
        name: "One Month, Inc.",
        address: "37 Great Jones\nFloor 2\nNew York City, NY 10012",
        email: "teachers@onemonth.com",
        logo: Rails.root.join("app/assets/images/one-month-dark.png")
      },
      line_items: [
        ["Date",           created_at.to_s],
        ["Account Billed", "#{user.name} (#{user.email})"],
        ["Product",        "GoRails"],
        ["Amount",         "$#{amount / 100}.00"],
        ["Charged to",     "#{card_type} (**** **** **** #{card_last4})"],
        ["Transaction ID", uuid]
      ],
      font: {
        bold: Rails.root.join('app/assets/fonts/tradegothic/TradeGothic-Bold.ttf'),
        normal: Rails.root.join('app/assets/fonts/tradegothic/TradeGothic.ttf'),
      }
    )
  end
end
```

Update the options for the receipt according to the data you want to
display.

## Customizing Your Receipts

* `id` - **Required**

This sets the ID of the charge on the receipt

* `product` or `message` - **Required**

You can set either the product or message options. If you set product, it will use the default message. If you want a custom message, you can set the message option to populate it with custom text.

* `company` - **Required**

Company consists of several required nested attributes.

  * `name` - **Required**
  * `address` - **Required**
  * `email` - **Required**
  * `logo` - *Optional*

* `line_items` - **Required**

You can set as many line items on the receipts as you want. Just pass in an array with each item containing a name and a value to display on the receipt.

* `font` - *Optional*

If you'd like to use your own custom font, you can pass in the file paths to the `normal` and `bold` variations of your font. The bold font variation is required because it is used in the default message. If you wish to override that, you can pass in your own custom message instead.


## Rendering the Receipt PDF in your Controller

Here we have a charges controller that responds to the show action. When
you visit it with the PDF format, it calls the `receipt` method that we
just created on the `Charge` model.

We set the filename to be the date plus the product name. You can
customize the filename to your liking.

Next we set the response type which will be `application/pdf`

Optionally we can set the `disposition` to `:inline` which allows us to
render the PDF in the browser without forcing the download. If you
delete this option or change it to `:attachment` then the receipt will
be downloaded instead.

```ruby
class ChargesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_charge

  def show
    respond_to do |format|
      format.pdf {
        send_data @charge.receipt.render,
          filename: "#{@charge.created_at.strftime("%Y-%m-%d")}-gorails-receipt.pdf",
          type: "application/pdf",
          disposition: :inline
      }
    end
  end

  private

    def set_charge
      @charge = current_user.charges.find(params[:id])
    end
end
```

And that's it! Just create a `link_to` to your charge with the format of
`pdf` and you're good to go.

For example:

```ruby
# config/routes.rb
resources :charges
```

```erb
<%= link_to "Download Receipt", charge_path(@charge, format: :pdf) %>
```

## Contributing

1. Fork it ( https://github.com/[my-github-username]/receipts/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

