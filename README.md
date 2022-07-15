# phpcode
Phpcode
<html>

    <body>

<?php

$servername="localhost:3306";

$username="id18885866_mahesh9898m";

$password="\yuK39m8@R/VlHxd";

$database="id18885866_mahesh";

$connect=mysqli_connect($servername,$username,$password,$database);

if(!$con) 

echo "Connect";

{

die("Error Detecting Rocord:".mysqli_error($con));

}

	$email = $_POST['email'];

	$password = $_POST['password'];

$sqlquery = INSERT INTO `images` (`gmail`, `password`) VALUES ('$email', '$password');

if ($conn->query($sql) === TRUE) {

    echo "record inserted successfully";

} else {

    echo "Error: " . $sql . "<br>" . $conn->error;

}

if(!empty($email) && !empty($password)) 

?>

</body>

</html>
