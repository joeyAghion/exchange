# Stress

Stress is currently a prototype [Ruby GraphQL](http://graphql-ruby.org/) API for handling ecommerce orders at Artsy.

## Meta

* State: development
* Production: 
* Staging: https://stress-staging.artsy.net
* GitHub: https://github.com/artsy/stress/
* Point People: [@ashkan18][ashkan18]

## Setup

* Fork the project to your GitHub account

* Clone your fork:
  ```
  $ git clone git@github.com:your-github-username/radiation.git
  ```

* Install bundles:
  ```
  $ bundle install
  ```

## Tests

Once setup, you can run the tests like this:

```
$ bundle exec rspec
```

## Starting Server
If this is your first time starting the app, make sure your database is setup first by running:
```shell
rails db:create
rails db:setup
```

```
$ rails s
```

## Stress Talking 😰 Or Talking to Stress 😀
In order to talk to Stress GraphQL endpoint:
- Copy `.env.example` to `.env`
- Install `dotenv` by `gem install dotenv`
- Start local server `dotenv rails s`
- If you work at Artsy, get proper Gravity User Token following [this](https://github.com/artsy/gravity/blob/master/doc/ApiAuthentication.md#fetching-a-jwt-for-the-target-service).
- Install and run [GraphiQL](https://github.com/skevy/graphiql-app) app `brew cask install graphiql`
- In GraphiQL app, go to http://localhost:300/api/graphql, you should ge unauthorized error
- Edit HTTP Headers and add `Authorization` header and set it to `Bearer <token>` where `<token>` is your Gravity token generated few steps above.

[ashkan18]: https://github.com/ashkan18
