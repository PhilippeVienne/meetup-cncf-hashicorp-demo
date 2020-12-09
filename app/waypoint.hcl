project = "meetup-app"

app "meetup-app" {
  labels = {
    "service" = "meetup-app",
    "env"     = "dev"
  }

  build {
    use "pack" {}
    registry {
      use "docker" {
        image = "philippevienne/meetup-app"
        tag   = "latest"
      }
    }
  }

  deploy {
    use "kubernetes" {
      probe_path = "/"
    }
  }

  release {
    use "kubernetes" {
      load_balancer = true
      port = 8080
    }
  }
}
