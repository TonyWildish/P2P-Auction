library('graphics')

xmax <- 20
ymax <- 20
x <- c(0, 5, 5, 10, 10, 15, 15, xmax)
y <- c(2, 2, 8,  8, 12, 12, 17, 17)

x1 <- append(x, c(xmax,0) )
y1 <- append(y, c(   0,0) )
plot(x,y,type='n',xlim=range(0,xmax), ylim=range(0,ymax))
polygon(x1, y1, angle=45, density=12)

# x2 <- seq(0,xmax,0.5)
# y2 <- sapply(x,FUN=function(p) { return( ymax - 3 - p/5) } )
# x <- x[1:6]
# x <- append(x, c(xmax,0) )
# y <- y[1:6]
# y <- append(y, c(   0,0) )
# polygon(x, y, angle=135, density=24)
