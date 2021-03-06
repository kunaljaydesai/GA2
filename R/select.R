###########################################################################################
# Function: select
#' Genetic Algorithm
#' @description Ranked each model by its fitness, Choose parents from generations propotional to their fitness. Then do crossover and mutation, Replace a proportion G of the worst old individuals by best new individuals
#' @param X: dataframe containing vairables in the model
#' @param y: vector targeted variable
#' @param C: The length of chromosomes, i.e. the maximum number of possible predictors.
#' @param family: a description of the error distribution and link function to be used in glm.
#' @param selection: selection mechanism. Can be either "proportional" or "tournament".
#' @param K: size of each round of selection when using tournament selection.
#'   Must be an integer smaller than generation size.
#' @param randomness: if TURE, one parent will be selected randomly
#' @param P: population size
#' @param G: proportion of worst-performing parents the user wishes to replace by best offspring
#' @param n_splits: number of crossover points to use in breeding
#' @param op: An optional, user-specified genetic operator function
#'   to carry out the breeding.
#' @param fit_func: Function for fitness measurement. Default is AIC.
#' @param max_iter: how many iterations to run before stopping
#' @return The best individual seen over all iterations. The best individual is characterized as the feature set that best explains the data.
#' @details First, the algorithm setups up the first generation of P models by randomly selecting features for each member of the generation. Once that was completed, the algorithm calculates the fitness of each model inside the generation and rank all the models by their fitness. The algorithm repeats this step till we reach the max number of iterations. Once this is complete, the feature set corresponding to the lowest AIC is returned.
#' @examples
#' x <- mtcars[-1]
#' y <- unlist(mtcars[1])
#' select(x, y, selection = "tournament", K = 5, randomness=TRUE, G=0.8)
#' set.seed(1)
#' n <- 500
#' C <- 40
#' X <- matrix(rnorm(n * C), nrow = n)
#' beta <- c(88, 0.1, 123, 4563, 1.23, 20)
#' y <- X[ ,1:6] %*% beta
#' colnames(X) <- c(paste("real", 1:6, sep = ""),
#'                  paste("noi", 1:34, sep = ""))
#' o1 <- select(X, y, nsplits = 3, max_iter = 10)
#' o2 <- select(X, y, selection = "proportional", n_splits = 3)
#' @export

select <- function(X, y, C = ncol(X), family = gaussian,
                   selection = "tournament", K = 2,
                   randomness = TRUE, P = 2 * ncol(X),
                   G = 1/P, n_splits = 2, op = NULL,
                   fit_func = AIC, max_iter = 100, parallel=TRUE, ...) {

  feature_count <- ncol(X)
  dict.fitness <<- new.env()
  initial <- initialize_parents(ncol(X), P)

  if (parallel) {
    cores <- parallel::detectCores()
    cluster <- parallel::makeCluster(cores)
    parallel::clusterExport(cluster, "crossover")
    parallel::clusterExport(cl = cluster, c("dict.fitness"),
                            envir = dict.fitness)
  } else {
    cluster = NA
  }

  old_gen <- ranked_models(initial$index, X, y, fit_func, cluster=cluster)
  fitness <- old_gen$fitness

  best <- c() ## best seen so far
  best_i <- 0 ## iteration when it was seen
  best_fit <- Inf ## fitness of best so far

  i <- 0   # number of iterations
  while(i < max_iter) {

    ##### select parents #####

    if (selection == "proportional"){
      parents <- propotional(old_gen, random = randomness)
    } else {
      parents <- tournament(old_gen, k=K)
    }

    ##### crossover and mutation #####
    if (parallel && all(!is.na(cluster))) {
      children <- unique(unlist(
        parallel::parLapply(cluster, parents,
                            breed, C, n_splits, op),
        FALSE, FALSE
      ))
    } else {
      children <- unique(unlist(lapply(parents, breed,
                                       C, n_splits, op),
                                FALSE, FALSE))
    }


    ##### ranked new generation and calculate fitness #####

    ranked_new <- ranked_models(children, X, y, fit_func,
                                cluster=cluster)

    ##### replace k worst old individuals with k new individuals #####

    next_gen <- generation_gap(old_gen, ranked_new, G)

    ## update our best so far if necessary
    if (next_gen$fitness[1] < best_fit) {
      best_fit <- next_gen$fitness[1]
      best <- next_gen$Index[[1]]
      best_i <- i + 1
    }

    ##### let new genration reproudce next offspring ######
    old_gen <- next_gen
    fitness <- old_gen$fitness
    i <- i + 1
  }
  if (all(!is.na(cluster))) {
    parallel::stopCluster(cluster)
  }

  summary <- list(survivor = best, fitness = best_fit,
                  num_iteration = i, first_seen = best_i)

  return(summary)
}
